USE [His_T24_Reports]
GO
WITH TRACK AS (
SELECT
COUNT(Customer_Id)AS COUNT_OF_LOANS
,Customer_Id
,MIN(Orig_Contract_Date)AS MIN_ORIG_CONTRACT_DATE

 ,CASE 
 WHEN MAX(PMA_Sector) = 1 THEN '17'
 WHEN MAX(PMA_Sector) = 2 THEN '2'
 WHEN MAX(PMA_Sector) = 3 THEN '2'
 WHEN MAX(PMA_Sector) = 4 THEN '7'
 WHEN MAX(PMA_Sector) = 5 THEN '15'
 WHEN MAX(PMA_Sector) = 6 THEN ''
 WHEN MAX(PMA_Sector) = 7 THEN ''
 WHEN MAX(PMA_Sector) = 8 THEN '5'
 WHEN MAX(PMA_Sector) = 9 THEN '5'
 END AS MAX_SECTOR

,CASE
     WHEN MAX(Contract_amount_USD) < 25000 THEN '3'
     WHEN MAX(Contract_amount_USD)BETWEEN 25000 AND 50000 THEN '2'
     WHEN MAX(Contract_amount_USD) > 50000 THEN '1'
 END AS [MAX_CONTRACT_USD]

,MAX(His_ARR_Account.Annual_Sales) AS MAX_Annual_Sales

FROM His_All_Full_Loans_Extract_Rate
LEFT JOIN His_ARR_Account ON His_ARR_Account.Arrangment_Id= His_All_Full_Loans_Extract_Rate.Arrangement
GROUP BY  Customer_Id
HAVING COUNT(Customer_Id) > 1 
) 
,
CONTARCT_AMOUNT_IN_USD AS (
SELECT 
His_All_Full_Loans_Extract.Arrangement AS [ARR],
CAST(His_All_Full_Loans_Extract.Contract_amount/His_Currancy.RATE AS decimal (20,3)) AS [Contract_Amount_USD_1]

FROM His_All_Full_Loans_Extract 
LEFT JOIN His_Currancy 
			ON His_Currancy.CURRANCY = His_All_Full_Loans_Extract.Loan_CCY
LEFT JOIN His_AALoans
			ON His_AALoans.AA_ARRANGEMENT = His_All_Full_Loans_Extract.Arrangement
WHERE 
His_Currancy.Date LIKE CONVERT(Date,Case When Orig_Contract_Date < '20190303' then '20190303' else Orig_Contract_Date end ,1)
AND
His_AALoans.ARR_STATUS in ('CURRENT','EXPIRED')
)
,RecoveryY AS (
 SELECT ARRANGEMENT AS ARRANGEMENT,
 SUM(ACCOUNT_USD) AS PRINCPLE ,
 His_ARR_Account.PS_DAT_ST_COURT
 FROM
His_ARR_Account LEFT JOIN V_His_All_Bills_PMT_Rate ON His_ARR_Account.Arrangment_Id = V_His_All_Bills_PMT_Rate.ARRANGEMENT
WHERE LEN(PS_DAT_ST_COURT) > 0 AND ARRANGEMENT IS NOT NULL
GROUP BY ARRANGEMENT,PS_DAT_ST_COURT
 )
 ,ARREAR_90 AS (

SELECT Arrangement,SUM(OS_PRINCIPALINT_USD) AS OS_PRINCIPALINT_USD , SUM (OS_ACCOUNT_USD) AS OS_ACCOUNT_USD FROM His_All_Full_Loans_Extract_Rate
LEFT JOIN His_AALoan_Bills_Rate ON His_All_Full_Loans_Extract_Rate.Arrangement = His_AALoan_Bills_Rate.ARRANGEMENT_ID
WHERE No#_of_days_due > 90 
GROUP BY Arrangement 

) ,X AS
  (SELECT COUNT(Arrangement) AS [Borrower_NumberOtherLoans],
          Customer_Id AS [Customer_Id]
   FROM His_All_Full_Loans_Extract_Rate
   LEFT JOIN His_AALoans ON His_AALoans.AA_ARRANGEMENT = His_All_Full_Loans_Extract_Rate.Arrangement
   WHERE His_AALoans.ARR_STATUS IN ('CURRENT',
                                    'EXPIRED')
   GROUP BY Customer_Id),
     Loan_Receivedcumulative AS
  (SELECT ARRANGEMENT_ID AS ARRANGEMENT_ID,
          ISNULL(SUM(OR_PRINCIPALINT_USD), 0) AS SUM_PRINCIPALINT,
          ISNULL(SUM(OR_ACCOUNT_USD), 0) AS SUM_PRINCIPAL
   FROM His_AALoan_Bills_Rate
   WHERE SETTLE_STATUS = 'REPAID'
     AND PAYMENT_INDICATOR = 'DEBIT'
   GROUP BY ARRANGEMENT_ID),
     DATE_OF_LAST_DUES_LOANS AS
  (SELECT ARRANGEMENT_ID AS ARRAN,
          MAX(PAYMENT_DATE) AS DATE_OF_LAST_DUES_LOANS
   FROM His_AALoan_Bills_Rate
   GROUP BY ARRANGEMENT_ID),
     COLLA_AMOUNT AS
  (SELECT FinalAAGuarantor.Arrangement AS Arrangement,
          MAX(ISNULL(CASE
                         WHEN Collateral_Type LIKE '6' THEN Nominal_Value
                         WHEN Collateral_Type LIKE '17' THEN Nominal_Value
                         WHEN Collateral_Type LIKE '12' THEN Nominal_Value
                     END, 0)) AS COLLA_AMOUNT
   FROM FinalAAGuarantor
   LEFT JOIN His_All_Collateral ON FinalAAGuarantor.COLLATERAL_ID=His_All_Collateral.Collateral_ID
   GROUP BY FinalAAGuarantor.Arrangement),
     GRA_AMOUNT AS
  (SELECT FinalAAGuarantor.Arrangement AS Arrangement,
          MAX(ISNULL(CASE
                         WHEN Collateral_Type LIKE '1' THEN Nominal_Value
                     END, 0)) AS KOM_AMOUNT,
          MAX(ISNULL(CASE
                         WHEN Collateral_Type LIKE '16' THEN Nominal_Value
                     END, 0)) AS RATB_AMOUNT
   FROM FinalAAGuarantor
   LEFT JOIN His_All_Collateral ON FinalAAGuarantor.COLLATERAL_ID=His_All_Collateral.Collateral_ID
   GROUP BY FinalAAGuarantor.Arrangement),
     DATE_OF_LAST_PAYMENT_DUE AS
  (SELECT Transaction_Ref AS Transaction_Ref,
          MAX(Completion_Date) AS DATE_OF_LAST_PAYMENT
   FROM his_loan_payments
   GROUP BY Transaction_Ref),
     CONTRACT_AMOUMT AS
  (SELECT Arrangement AS Arrangement,
          Contract_amount_USD AS Contract_amount_USD
   FROM His_All_Full_Loans_Extract_Rate)

   --,OS_THIS_MONTH AS(
   --SELECT
   --Arrangement,
   --OS_AMT_PORTFOLIO_USD 
   --FROM
   --His_Full_Loans_Extract_Rate WHERE His_Full_Loans_Extract_Rate.Loan_CCY = 'USD' AND change_date LIKE '2023-07-31'
   --)
   ,OS_PER_MONTH AS(
   SELECT
   Arrangement,
   OS_AMT_PORTFOLIO_USD 
   FROM
   His_Full_Loans_Extract_Rate WHERE His_Full_Loans_Extract_Rate.Loan_CCY = 'USD' AND change_date LIKE '2023-05-31'
   )
SELECT
 FORMAT(His_Full_Loans_Extract_Rate.change_date, 'yyyyMMdd') AS [Reporting_Date],
 'FATEN' AS [Originator_Name],
 '251' AS [Originator_Country],
 '' AS [Originator_Rating],
 '' AS [Originator_CreditQualityAssessment],
 CASE 
 WHEN Loan_CCY = 'ILS' THEN '1'
 WHEN Loan_CCY = 'USD' THEN '0'
 END
 AS [Originator_TargetGroupSmartApproach_YN],
 TRIM(His_Full_Loans_Extract_Rate.Arrangement) AS [Loan_ID],
 'USD' AS [Loan_Currency_code],
 isnull(CONTARCT_AMOUNT_IN_USD.[Contract_Amount_USD_1],0) AS [Loan_BalanceOriginal],
 His_Full_Loans_Extract_Rate.Contract_amount_USD AS [Loan_BalanceDisbursed],
 His_Full_Loans_Extract_Rate.OS_AMT_PORTFOLIO_USD AS [Loan_BalanceCurrent],
 His_Full_Loans_Extract_Rate.Orig_Contract_Date AS [Loan_StartDate],
 His_Full_Loans_Extract_Rate.Maturity_date AS [Loan_EndDate],
 DATEDIFF(MONTH, His_Full_Loans_Extract_Rate.Orig_Contract_Date, His_Full_Loans_Extract_Rate.Maturity_date) AS [Loan_TenureMonths],
 '1' AS [Loan_TypeInterest],
 CAST((His_Full_Loans_Extract_Rate.Effective_Interest_Rate/100.00)AS Decimal(10, 2)) AS [Loan_InterestRateEffective],
 '5' AS [Loan_TypeRepayment],
 '0' AS [Loan_GroupLoan_YN],
 His_Full_Loans_Extract_Rate.Orig_Contract_Date AS [Loan_OfferDate],
 '1' AS [Loan_PaymentFrequency],
 '' AS [Loan_Purpose],
 CASE
     WHEN His_Full_Loans_Extract_Rate.Contract_amount_USD < 25000 THEN '1'
     WHEN His_Full_Loans_Extract_Rate.Contract_amount_USD BETWEEN 25000 AND 50000 THEN '2'
     WHEN His_Full_Loans_Extract_Rate.Contract_amount_USD > 50000 THEN '3'
 END AS [Loan_Segment],
 His_Loan_Paymernts_Rate.Interest_USD AS [Loan_Installment_first_monthly_interest],
 His_Loan_Paymernts_Rate.Principal_USD AS [Loan_Installment_first_monthly_principal],
 His_Loan_Paymernts_Rate.total_USD AS [Loan_MonthlyInstallment],
 '' AS [Loan_scheduled_principal_installment],
 ISNULL(Loan_Receivedcumulative.SUM_PRINCIPALINT, 0) AS [Loan_ReceivedInterest_cumulative],
 ISNULL(Loan_Receivedcumulative.SUM_PRINCIPAL, 0) AS [Loan_ReceivedPrincipal_cumulative],
 '' AS [Loan_ReceivedPenalties_cumulative],
 CASE
     WHEN No#_of_days_due BETWEEN 0 AND 30 THEN '1'
     WHEN No#_of_days_due BETWEEN 31 AND 89 THEN '2'
     WHEN No#_of_days_due >= 90 THEN '3'
 END AS [Loan_Status],
 '' AS [Loan_Status_ChangeDate],
 CASE
     WHEN His_Full_Loans_Extract_Rate.PS_RESTRUCTURED = 'YES' THEN '1'
     WHEN His_Full_Loans_Extract_Rate.PS_RESTRUCTURED = 'NO' THEN '0'
 END AS [Loan_Restructured_YN],
 CASE
     WHEN His_Full_Loans_Extract_Rate.PS_RESTRUCTURED = 'YES' THEN '0'
     WHEN His_Full_Loans_Extract_Rate.PS_RESTRUCTURED = 'NO' THEN ''
 END AS [Loan_RestructuredAmount_CumulativeLoss],
 His_Full_Loans_Extract_Rate.No#_of_days_due AS [Loan_Arrear_days],
 DATEDIFF(MONTH, convert(date, Orig_Contract_Date, 23), isnull(Start_Payment_Bisan.payment_date, PAYMENT_START_DATE)) AS [Loan_GracePeriodMonths],
 CASE
     WHEN DATE_OF_LAST_DUES_LOANS.DATE_OF_LAST_DUES_LOANS = His_Full_Loans_Extract_Rate.Orig_Contract_Date THEN ''
     WHEN DATE_OF_LAST_DUES_LOANS.DATE_OF_LAST_DUES_LOANS <> His_Full_Loans_Extract_Rate.Orig_Contract_Date THEN ISNULL(FORMAT(DATE_OF_LAST_DUES_LOANS.DATE_OF_LAST_DUES_LOANS, 'yyyyMMdd'), '')
 END AS [Loan_LastDueDate],

 Trim(ISNULL(DATE_OF_LAST_PAYMENT_DUE.DATE_OF_LAST_PAYMENT, '')) AS [Loan_LastPaymentDate],
 ISNULL(ARREAR_90.OS_ACCOUNT_USD,0) AS [Loan_ArrearAmountPrincipal],
 ISNULL(ARREAR_90.OS_PRINCIPALINT_USD,0) AS [Loan_ArrearsAmountInterest],
 '0' AS [Loan_ArrearAmountPenalties],
 ISNULL(COLLA_AMOUNT.COLLA_AMOUNT,0) AS [Loan_CollateralAmount],
 ISNULL(GRA_AMOUNT.KOM_AMOUNT+GRA_AMOUNT.RATB_AMOUNT,0) AS [Loan_GuaranteeAmount],
 ISNULL(RecoveryY.PRINCPLE,0) AS [Loan_RecoveryAmount_Cumulative],
 '' AS [Loan_RecoveryCosts_Cumulative],
  CASE WHEN No#_of_days_due >=  31 THEN ISNULL(RecoveryY.PS_DAT_ST_COURT,0) ELSE 0 END  AS [Loan_RecoveryEnd_date],
 His_Full_Loans_Extract_Rate.Customer_Id AS [Borrower_ID],
 CASE
     WHEN His_Customer_Data_Final.CUST_TYPE = 'I' THEN '1'
     WHEN His_Customer_Data_Final.CUST_TYPE = 'NI' THEN '0'
 END AS [Borrower_NaturalPerson_YN],
 '251' AS [Borrower_Location_Country],
 CASE
     WHEN His_Customer_Data_Final.DES_GVNT_PERS LIKE '%GAZA%' THEN 'GAZA'
     WHEN His_Customer_Data_Final.DES_GVNT_PERS LIKE '%RAFAH%' THEN 'GAZA'
     WHEN His_Customer_Data_Final.DES_GVNT_PERS like '%KHAN YOUNIS%' THEN 'GAZA'
     WHEN His_Customer_Data_Final.DES_GVNT_PERS LIKE '%DIER AL-BALAH%' THEN 'GAZA'
     WHEN His_Customer_Data_Final.DES_GVNT_PERS LIKE '%Beit Lahia%' THEN 'GAZA'
     WHEN His_Customer_Data_Final.DES_GVNT_PERS like '%Jabalia%' THEN 'GAZA'
     WHEN His_Customer_Data_Final.DES_GVNT_PERS like '%Bani Suheila%' THEN 'GAZA'
     ELSE 'WEST BANK'
 END AS [Borrower_Location_Region],
 '' AS [Borrower_Credit_score],
 '1' AS [Borrower_Guarantor_YN],
 CASE
     WHEN His_Customer_Data_Final.GENDER = 'FEMALE' THEN '1'
     WHEN His_Customer_Data_Final.GENDER = 'MALE' THEN '2'
     WHEN His_Customer_Data_Final.GENDER = 'OTHER'THEN '3'
 END AS [Borrower_Gender],
 CASE
     WHEN His_Customer_Data_Final.MARITAL_STATUS = 'MARRIED' THEN '1'
     WHEN His_Customer_Data_Final.MARITAL_STATUS = 'SINGLE' THEN '2'
     WHEN His_Customer_Data_Final.MARITAL_STATUS = 'DIVORCED' THEN '3'
     WHEN His_Customer_Data_Final.MARITAL_STATUS = 'WIDOW' THEN '4'
     WHEN His_Customer_Data_Final.MARITAL_STATUS = 'SEPARATED' THEN ''
     WHEN ISNULL(His_Customer_Data_Final.MARITAL_STATUS, '') = '' THEN ''
 END AS [Borrower_Marital_status],
 '0' AS [Borrower_MigrantStatus_YN],
 TRIM(ISNULL(His_Customer_Data_Final.NO_OF_DEPEND, '')) AS [Borrower_Dependents],
 
 CASE 
 WHEN ( His_Customer_Data_Final.BIRTH_INCORP_DATE IS NULL  OR  His_Customer_Data_Final.ID_TYPE = '6' ) THEN '' 
 ELSE
 ISNULL(CONCAT(SUBSTRING(His_Customer_Data_Final.BIRTH_INCORP_DATE, 1, 4), '0101'), '')
 END AS [Borrower_DateOfBirth],

'' AS [Borrower_Insurance_YN],
 X.Borrower_NumberOtherLoans AS [Borrower_NumberOtherLoans],
 '5' AS [Borrower_RealEstateSituation],
 
 CASE
     WHEN His_Customer_Data_Final.ID_TYPE = '6' THEN CONCAT(SUBSTRING(His_Customer_Data_Final.BIRTH_INCORP_DATE, 1, 3),0)
	 ELSE
	 ''
 END AS [Borrower_FoundingYear],

 CASE
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_SECTOR
 ELSE
 CASE 
 WHEN Sector.Sector_id = 1 THEN '17'
 WHEN Sector.Sector_id = 2 THEN '2'
 WHEN Sector.Sector_id = 3 THEN '2'
 WHEN Sector.Sector_id = 4 THEN '7'
 WHEN Sector.Sector_id = 5 THEN '15'
 WHEN Sector.Sector_id = 6 THEN ''
 WHEN Sector.Sector_id = 7 THEN ''
 WHEN Sector.Sector_id = 8 THEN '5'
 WHEN Sector.Sector_id = 9 THEN '5'
 END
 END AS [Borrower_IndustryCode] ,
 '251' AS [Borrower_TaxResidenceCountry],
 CASE
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN DATEDIFF(YEAR,TRACK.MIN_ORIG_CONTRACT_DATE, CAST(GETDATE ()AS DATE))
 ELSE
 DATEDIFF(YEAR,His_Full_Loans_Extract_Rate.Orig_Contract_Date, CAST(GETDATE ()AS DATE)) END AS [Borrower_TrackRecord],
 CASE
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_CONTRACT_USD
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_CONTRACT_USD
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_CONTRACT_USD
 ELSE
 CASE
     WHEN His_Full_Loans_Extract_Rate.Contract_amount_USD < 25000 THEN '3'
     WHEN His_Full_Loans_Extract_Rate.Contract_amount_USD BETWEEN 25000 AND 50000 THEN '2'
     WHEN His_Full_Loans_Extract_Rate.Contract_amount_USD > 50000 THEN '1' END
 END AS [Borrower_SizeSML],
 '' AS [Borrower_Acc_Assets],
 '' AS [Borrower_Acc_AssetsShortTerm],
 '' AS [Borrower_Acc_AuditLevel],
 '' AS [Borrower_Acc_DebtExposure],
 '' AS [Borrower_Acc_EBITDA],
 '' AS [Borrower_Acc_Equity],
 '' AS [Borrower_Acc_InterestExpense],
 '' AS [Borrower_Acc_LiabilitiesShortTerm],
 '' AS [Borrower_Acc_NetProfit],

 CASE 
 WHEN TRACK.COUNT_OF_LOANS > 1 THEN TRACK.MAX_Annual_Sales 
 ELSE His_ARR_Account.Annual_Sales
 END
 AS [Borrower_Acc_Sales_currentyear],
 '' AS [Borrower_Acc_Sales_previousyear],
 '' AS [Borrower_Acc_SalesMonthly],
 '' AS [Borrower_Acc_EnterpriseValue],
 '' AS [Borrower_Acc_FreeCashflow],
 '' AS [Borrower_Acc_YearFinancialInfo],
 '' AS [Borrower_Acc_CCYFinancialInfo],
 '' AS [Loan_Prepayment_Lock_Out_End_Date],
 '' AS [Loan_PrepaymentFee],
 '' AS [Loan_PrepaymentFeeEndDate],
 '' AS [Loan_PrepaymentDate],
 '' AS [Loan_CumulativePrepayments],
 '1' AS [Loan_SecurityType],
 '5' AS [Loan_ChargeType],
 '5' AS [Loan_CollateralType],
 '5' AS [Loan_CurrentValuationMethod],
 '5' AS [Loan_OriginalValuationMethod],
 '' AS [Loan_DateOfSale],
 '' AS [Loan_Sale_Price],
 CASE
 WHEN His_Full_Loans_Extract_Rate.OS_AMT_PORTFOLIO_USD > OS_PER_MONTH.OS_AMT_PORTFOLIO_USD THEN '1'
 ELSE '0'
 END AS [FLAG]
 --OS_PER_MONTH.OS_AMT_PORTFOLIO_USD AS [OS_PRE_MONTH],
 --His_Full_Loans_Extract_Rate.OS_AMT_PORTFOLIO_USD AS [OS_THIS_MONTH]

FROM His_Full_Loans_Extract_Rate
LEFT JOIN His_AALoans_Rate ON His_AALoans_Rate.AA_ARRANGEMENT = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN Activity ON Activity.id = His_Full_Loans_Extract_Rate.Economic_Activity
LEFT JOIN His_Loan_Paymernts_Rate ON His_Loan_Paymernts_Rate.Transaction_Ref = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN Start_Payment_Bisan ON Start_Payment_Bisan.legacy_id = CASE
                                                                     WHEN len(His_Full_Loans_Extract_Rate.Legacy_Id) = 9 THEN CONCAT('0', His_Full_Loans_Extract_Rate.Legacy_Id)
                                                                     ELSE His_Full_Loans_Extract_Rate.Legacy_Id
                                                                 END
LEFT JOIN His_Customer_Data_Final ON His_Customer_Data_Final.id = His_Full_Loans_Extract_Rate.Customer_Id
LEFT JOIN X ON X.Customer_Id = His_Full_Loans_Extract_Rate.Customer_Id
LEFT JOIN V_Last_Installment_Paid_Date ON V_Last_Installment_Paid_Date.ARRANGEMENT_ID = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN His_T24_Close_Loans_Extract ON His_T24_Close_Loans_Extract.Arrangement = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN His_Loan_Insuranc ON His_Loan_Insuranc.loans = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN Loan_Receivedcumulative ON Loan_Receivedcumulative.ARRANGEMENT_ID = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN DATE_OF_LAST_DUES_LOANS ON DATE_OF_LAST_DUES_LOANS.ARRAN = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN COLLA_AMOUNT ON COLLA_AMOUNT.Arrangement = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN GRA_AMOUNT ON GRA_AMOUNT.Arrangement = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN His_ARR_Account ON His_ARR_Account.Arrangment_Id = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN DATE_OF_LAST_PAYMENT_DUE ON DATE_OF_LAST_PAYMENT_DUE.Transaction_Ref = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN CONTRACT_AMOUMT ON CONTRACT_AMOUMT.Arrangement = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN His_T24_Woff_Loans_Amount ON His_T24_Woff_Loans_Amount.Arrangement = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN Sector ON Sector.Sector_id = His_Full_Loans_Extract_Rate.PMA_Sector
LEFT JOIN ARREAR_90 ON ARREAR_90.Arrangement = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN RecoveryY ON RecoveryY.ARRANGEMENT = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN TRACK ON TRACK.Customer_Id = His_Full_Loans_Extract_Rate.Customer_Id
LEFT JOIN CONTARCT_AMOUNT_IN_USD ON CONTARCT_AMOUNT_IN_USD.[ARR] =His_Full_Loans_Extract_Rate.Arrangement
--LEFT JOIN OS_THIS_MONTH ON OS_THIS_MONTH.Arrangement = His_Full_Loans_Extract_Rate.Arrangement
LEFT JOIN OS_PER_MONTH ON OS_PER_MONTH.Arrangement = His_Full_Loans_Extract_Rate.Arrangement
WHERE
His_AALoans_Rate.ARR_STATUS IN ('CURRENT','EXPIRED')
AND Payment_Number = 2
AND His_Full_Loans_Extract_Rate.change_date IN
(
--'2023-05-31'
--,
'2023-06-30'
--,
--'2023-07-31'
)
--,'2023-06-30','2023-05-30')
--AND His_Full_Loans_Extract_Rate.Arrangement NOT IN (
--'AA190602SBXV',
--'AA190602XVCC',
--'AA190603QV7N',
--'AA190605FTSZ',
--'AA190606VGVT',
--'AA190608840R',
--'AA190609RLSD',
--'AA19060B7W74',
--'AA19060CGC2B',
--'AA19060D4291',
--'AA19060FK0KR',
--'AA19060GK3NH',
--'AA19060H1Y5C',
--'AA19060HLD4X',
--'AA19060JFL5R',
--'AA19060K8H86',
--'AA19060KHF6V',
--'AA19060L7ZRS',
--'AA19060MFY5Y',
--'AA19060P7NHZ',
--'AA19060SBR32',
--'AA19060T9MMM',
--'AA19060TSDBZ',
--'AA19060VNC1B',
--'AA19060WP0SR',
--'AA19060WRPKJ',
--'AA19060YDMPF',
--'AA19060Z0FK3',
--'AA19060Z36PW',
--'AA19060ZT2FB',
--'AA190901GK21',
--'AA191064QPZL',
--'AA19169T1CZK',
--'AA19174DYBJM',
--'AA19177LD2DG',
--'AA19177QYXV1',
--'AA19178XL47N',
--'AA19181PR5H8',
--'AA191993TRWT',
--'AA19210Q143V',
--'AA192120JHK1',
--'AA19212MFXDR',
--'AA19238ZZQ3G',
--'AA192414KRY0',
--'AA19241LT26Z',
--'AA19258J9FXV',
--'AA192619KZV2',
--'AA19265VP6DY',
--'AA19266R7514',
--'AA19268F2L3Y',
--'AA1927318Z36',
--'AA19273K08FH',
--'AA19287KJXPH',
--'AA19289CJ48J',
--'AA192936R4HR',
--'AA19295FVGWQ',
--'AA19296QQB65',
--'AA19302NTCDP',
--'AA193040FKQ6',
--'AA193155Z5C6',
--'AA19318Q1P2D',
--'AA193286WN68',
--'AA19331ZZ0DY',
--'AA19338W1YXG',
--'AA19346L9VZZ',
--'AA19356V58S3',
--'AA19358L9MDH',
--'AA1936575TZX',
--'AA193657ZY4H',
--'AA200192Z61W',
--'AA20019DV1QN',
--'AA20027NXN1C',
--'AA20030Y4CDL',
--'AA20044QH0R3',
--'AA20048WSRS5',
--'AA20051B92HS',
--'AA20055HTXZG',
--'AA20057FHFJZ',
--'AA20058Y283R',
--'AA20121RS7B6',
--'AA20140KZCLW',
--'AA20163J8ML4',
--'AA20173L9DZB',
--'AA20173RYBWX',
--'AA20182X9Q0J',
--'AA201903B1L3',
--'AA2022952HSD',
--'AA20230XDYZP',
--'AA2023149VXC',
--'AA202314NHK9',
--'AA2023187C5N',
--'AA20231NPJV0',
--'AA20233LSPVP',
--'AA20233P7QDS',
--'AA202362V6J6',
--'AA20236HXW6B',
--'AA20236NSRCW',
--'AA20236S4221',
--'AA20236Y60KN',
--'AA20237GF3BB',
--'AA202386V618',
--'AA20238BFLNJ',
--'AA20238WRJS0',
--'AA20243MXCV6',
--'AA202446N4YS',
--'AA202449F101',
--'AA20244D5RRR',
--'AA20244FCQWN',
--'AA20244L4J57',
--'AA20244MKX02',
--'AA20244PM8JV',
--'AA20244QJW7X',
--'AA20244T8VWR',
--'AA20244TRKMV',
--'AA20244VQFV0',
--'AA20244Z7LXB',
--'AA20253X1GS2',
--'AA20254SPRS3',
--'AA20257PYNGG',
--'AA20257YV09T',
--'AA20258J30YX',
--'AA202643RNMK',
--'AA20264TMKQZ',
--'AA20271Q0H91',
--'AA20271WX1Z4',
--'AA20273H66T0',
--'AA202745XYLL',
--'AA20274VM81T',
--'AA20281BY2GY',
--'AA202929X3SV',
--'AA20292QNB56',
--'AA20299BWFD9',
--'AA20300ZGYLG',
--'AA203017K6SF',
--'AA20302KZMH7',
--'AA20302YPT44',
--'AA203132GW2H',
--'AA20313ZRY0P',
--'AA2031406GNK',
--'AA20314NY3ML',
--'AA20315G8K5Q',
--'AA20315VTHG4',
--'AA20315X3QWQ',
--'AA20315XQ37R',
--'AA20316DMN93',
--'AA20316G0BKK',
--'AA20316KMVBJ',
--'AA20316SF9TM',
--'AA20322FJMBW',
--'AA20322GBCKZ',
--'AA20322WRDVS',
--'AA20322WW3Y5',
--'AA20322XQDLV',
--'AA2032304SQ8',
--'AA203233SGCL',
--'AA20323BG246',
--'AA20323QTMDT',
--'AA20323VRSRR',
--'AA203271CBVK',
--'AA2032730WMD',
--'AA203273HZB3',
--'AA203274QX6G',
--'AA203275JKZ5',
--'AA20327B09QS',
--'AA20327DMFFZ',
--'AA20327FKK7R',
--'AA20327TR0W8',
--'AA20327TRD2S',
--'AA203289F2XV',
--'AA20328Q6ZJN',
--'AA20329HMKHK',
--'AA20331NHWPJ',
--'AA203355STRR',
--'AA20335PS4N8',
--'AA2033608BZJ',
--'AA20336FHQNG',
--'AA20336FYBTL',
--'AA20336TYTXC',
--'AA2034120JYJ',
--'AA2034121HQM',
--'AA203412FZGY',
--'AA20341FP5Y4',
--'AA20341QJ1JZ',
--'AA20341R56F8',
--'AA20341T12PW',
--'AA20341XR6GT',
--'AA20342DBJJB',
--'AA20342L2S18',
--'AA20342VNTYD',
--'AA20343MRPZC',
--'AA20343NLH91',
--'AA20352SKK2Y',
--'AA2035546H1R',
--'AA20355F2147',
--'AA20362NGNLT',
--'AA20364S6SK3',
--'AA20365CM6GZ',
--'AA203660V7CD',
--'AA20366CRR9G',
--'AA210196QP7C',
--'AA21021Q4BLT',
--'AA2102786TBD',
--'AA210284XD0T',
--'AA21031BF1W0',
--'AA21031DGK97',
--'AA21035Z6W03',
--'AA21040PD7WQ',
--'AA21053ZK5WL',
--'AA21055QNZF0',
--'AA21056N1HTC',
--'AA210598YKR6',
--'AA21080W0VMD',
--'AA21087PP9GN',
--'AA2109161HCN',
--'AA210941C075',
--'AA211014FRND',
--'AA211158G9ZF',
--'AA21115R2K70',
--'AA21117N9D30',
--'AA21117TZFVN',
--'AA21119M1LCH',
--'AA211372VGLC',
--'AA211395N9D4',
--'AA2114374PDQ',
--'AA21145F49CK',
--'AA211472VM63',
--'AA21150LT5V2',
--'AA21150TKKXW',
--'AA21164CZW68',
--'AA211653NW4C',
--'AA211656GKLN',
--'AA21165R7K6T',
--'AA21165VTX54',
--'AA211663W4CP',
--'AA21166NKSFV',
--'AA21167JMSLC',
--'AA21171FJ8FB',
--'AA21171GJWXM',
--'AA21171VSY6Y',
--'AA211736K8GR',
--'AA211736S58Y',
--'AA21173JKZXY',
--'AA211744CSM9',
--'AA2117450TRV',
--'AA21174CHZ77',
--'AA211753NZB4',
--'AA21175S6C3V',
--'AA21178DCG4L',
--'AA21179TK0Q7',
--'AA211801X74Z',
--'AA21180KWYBM',
--'AA21181M3JK9',
--'AA211853Q1BN',
--'AA211857HTSZ',
--'AA211861GQND',
--'AA211866V69J',
--'AA21186H1CQ4',
--'AA21186RB9NT',
--'AA21186VYH9D',
--'AA211871FFQ5',
--'AA211872CL3M',
--'AA21187CP0S7',
--'AA21187FX89D',
--'AA21187HXVY8',
--'AA211883X2D6',
--'AA2118842PFD',
--'AA21188C0HK7',
--'AA211891S3GM',
--'AA21192364X3',
--'AA211925QM3D',
--'AA2119271BHM',
--'AA21192H0MCW',
--'AA21192LN7QS',
--'AA21192YQ9T5',
--'AA21193RSH1M',
--'AA21193XMHP5',
--'AA21195F11P9',
--'AA21195K7MR9',
--'AA21195MX8YL',
--'AA21195THRW8',
--'AA21195TVWMS',
--'AA21207FS7HD',
--'AA21210183CL',
--'AA212108ZJRY',
--'AA212140HN6Y',
--'AA21214GH7M4',
--'AA21214JY4T6',
--'AA21214LB0N7',
--'AA21214PHNKL',
--'AA21214WWC53',
--'AA21214ZZZXX',
--'AA21215DP7YP',
--'AA21215VHMKM',
--'AA21215VS98N',
--'AA21215X9P9R',
--'AA21215YBJF5',
--'AA212160X7LQ',
--'AA21216CF139',
--'AA21216P6JV6',
--'AA21216SC96K',
--'AA21216V62D6',
--'AA2122084PG4',
--'AA2122088MNY',
--'AA212224DXQ1',
--'AA21222BSH64',
--'AA21222D7XWL',
--'AA21222FPXKK',
--'AA21222SGMHN',
--'AA21222TPWSG',
--'AA212230K2J7',
--'AA21223G8BWD',
--'AA21223S5RLB',
--'AA21223T1Z1K',
--'AA21223YFVK8',
--'AA2122403S0F',
--'AA212274XP70',
--'AA212277QVFR',
--'AA21228VBX2D',
--'AA21235NK2SF',
--'AA21237M97T6',
--'AA21250H1LP5',
--'AA21250W49HG',
--'AA21256CHJQK',
--'AA212579336M',
--'AA21258MLRB5',
--'AA21262761B0',
--'AA21264M0CC9',
--'AA21264MWYQC',
--'AA21273CTGHS',
--'AA21299WSQNQ',
--'AA213003B075',
--'AA21304RSM4F',
--'AA21306416XN',
--'AA213068NRLX',
--'AA213080T29P',
--'AA21308KFF37',
--'AA213185R77S',
--'AA2132110QQQ',
--'AA213214Y24R',
--'AA21321ZXZ1B',
--'AA213222M58N',
--'AA21325DMW3N',
--'AA213263CRK7',
--'AA21326SPSCZ',
--'AA21333PWFNS',
--'AA21333YNZNZ',
--'AA21349M0V86',
--'AA2135387GFB',
--'AA21353M9MDH',
--'AA213609GXP2',
--'AA21360R28W0',
--'AA213647WL8R',
--'AA22010X0QJB',
--'AA22012Y480T',
--'AA22013JWF08',
--'AA22013Q2F26',
--'AA22016L9CR3',
--'AA220173XVYD',
--'AA22017QG2YM',
--'AA22025XS03F',
--'AA22033YGT3L',
--'AA22037F4FD5',
--'AA2204816GGX',
--'AA22058HCFH2',
--'AA220879BPX0',
--'AA22107TCS7T',
--'AA22118LHX6W',
--'AA22142HV7Q3',
--'AA22146K9H8M',
--'AA22149Z79PX',
--'AA2215154LH6',
--'AA2217376F30',
--'AA22178F5XTK',
--'AA22181TRLD3',
--'AA22226SSDGV',
--'AA22228WSJ08',
--'AA22279F93DZ',
--'AA22325XHRSH',
--'AA22334TR861',
--'AA22354Z0SS9'
--)
--LIKE '%AA190602SBXV%'
ORDER BY AA_ARRANGEMENT , Reporting_Date DESC;


/*
select
--Arrangement,OS_AMT_PORTFOLIO_USD,change_date,No#_of_days_due 
*
from His_Full_Loans_Extract_Rate where  His_Full_Loans_Extract_Rate.change_date IN('2023-05-31','2023-06-30','2023-07-31') and Arrangement
in (
'AA190602SBXV',
'AA190603QV7N',
'AA190609RLSD',
'AA19060VNC1B',
'AA20244FCQWN'
)
order by Arrangement,change_date desc;
*/



--select Arrangement,OS_AMT_PORTFOLIO_USD,His_Full_Loans_Extract_Rate.change_date,No#_of_days_due,Orig_Contract_Date
--from His_Full_Loans_Extract_Rate
--LEFT JOIN His_AALoans ON His_AALoans.AA_ARRANGEMENT = His_Full_Loans_Extract_Rate.Arrangement
--where
--His_Full_Loans_Extract_Rate.change_date IN('2023-05-31','2023-06-30',
--'2023-07-31')
--AND His_AALoans.ARR_STATUS IN ('CURRENT','EXPIRED')
--AND
--AA_ARRANGEMENT IN
--(
--'AA202449F101',
--'AA22258YZ4MR'

--)
--order by Arrangement,change_date desc;

