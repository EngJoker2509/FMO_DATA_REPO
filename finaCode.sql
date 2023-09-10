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
--AND 
--His_All_Full_Loans_Extract.Arrangement LIKE '%AA19060WG8PS%'

)
,RecoveryY AS (
 SELECT ARRANGEMENT AS ARRANGEMENT, SUM(ACCOUNT_USD) AS PRINCPLE ,His_ARR_Account.PS_DAT_ST_COURT  FROM
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
 '' AS [Loan_Sale_Price]
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
WHERE
His_AALoans_Rate.ARR_STATUS IN ('CURRENT','EXPIRED')
AND Payment_Number = 2
AND His_Full_Loans_Extract_Rate.change_date IN('2023-05-31')
--,'2023-06-30','2023-05-30')
--AND His_Full_Loans_Extract_Rate.Arrangement LIKE '%AA19060WG8PS%'
ORDER BY AA_ARRANGEMENT , Reporting_Date DESC;
