USE [adminsys]
GO
/****** Object:  StoredProcedure [dbo].[usp_FBoPEnrollmentNewLCSInsured_insert]    Script Date: 8/2/2017 1:50:49 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[usp_FBoPEnrollmentNewLCSInsured_insert]

AS
/*******************************************************************************
Object:  usp_FBoPEnrollmentNewLCSInsured_insert

Arguments:	none

Description:  add LCS eligibility & claim authorization from Dynamo for FBoP insureds/inmates

International Medical Group

Revision History:

Date        Project		Author          Comments
2017/05/17	80423		J. Beckom		Created
2017/05/29	80423		J. Beckom		update ClaimAuthorization load to avoid unique key constraint violation
2017/05/29	80423		J. Beckom		moved log update from SSIS into SProc, to alleviate redundancy
2017/05/31	80423		J. Beckom		added columns to coverage assignment insert (TerminationDate, PrintHipaa, AutoAdjustmentIndicator, CreditableCoverage)
2017/06/05	80423		J. Beckom		add country code to EligibilityInsured record, set LCS_SQL.dbo.EligibilityCoverageAssignment = '01', modify keydate calculation for EligibilityCoverageAssignment insert
2017/07/25	84027		J. Beckom		modify WHERE clause for ClaimAuthorization load to include appointment numbers from staging that don't currently exist in ClaimAuthorization
*******************************************************************************/

/*** LOCAL VARIABLES -- TRANSACTION MANAGEMENT & ERROR HANDLING ***/

SET NOCOUNT ON;

DECLARE	 @ls_error_message				VARCHAR(255)	=	''												-- set error text when raising error
		,@lvc_procedure_name			SYSNAME			=	'dbo.usp_FBoPEnrollmentNewLCSInsured_insert'	-- procedure name
		,@li_begin_tran_ind				TINYINT			=	0												-- TRAN indicator(0=No BEGIN TRAN, 1=BEGIN TRAN executed)
		,@li_raiserror_ind				TINYINT			=	0												-- RAISERROR indicator(0=Do NOT call RAISERROR, 1=call RAISERROR)
		,@li_rowcount					INT				=	NULL											-- store @@ROWCOUNT after INSERT/UPDATE
		,@li_error						INT				=	0												-- save @@ERROR
		,@ai_override_tran_management	TINYINT			=	0
		,@li_return						INT				=	0

IF	@ai_override_tran_management = 0
	OR
	@ai_override_tran_management IS NULL

	BEGIN		/*** no more than 1 transaction should be open ***/
		 IF @@TRANCOUNT	NOT IN (0,1)
			 BEGIN		/*** too many transactions! ***/
				  SET @li_begin_tran_ind	= 0
				  SET @li_raiserror_ind		= 1
				  SET @ls_error_message		= 'Invalid @@TRANCOUNT ( ' + CONVERT(char(4), @@TRANCOUNT )+ ' ) in ' + @lvc_procedure_name + '.'
				  GOTO Procedure_Exit
			 END
     
		 IF @@TRANCOUNT	= 1
			 BEGIN		/*** couldn't open new transaction ***/
				SET @li_begin_tran_ind = 0
			 END
		 ELSE	BEGIN		/*** open new tran ***/
			  BEGIN TRAN
				SET @li_error = @@ERROR
				  IF (		/*** did it work? ***/
						@li_error <> 0
						OR
						@@TRANCOUNT <> 1
				  )
					  BEGIN		/*** open tran failed, abandon ship!! ***/
						   SET @li_begin_tran_ind         = 0
						   SET @li_raiserror_ind          = 1
						   SET @ls_error_message          = 'BEGIN TRAN failed in ' + @lvc_procedure_name + '.'
						   GOTO Procedure_Exit
					  END
				ELSE SET @li_begin_tran_ind = 1		/*** it worked, you may continue ***/
		 END
	END

/*** START PROCESSING ***/

IF OBJECT_ID ('tempdb..#insureds','U') IS NOT NULL
	BEGIN
		DROP TABLE #insureds
	END

	CREATE TABLE #insureds (
		 insuredID		NUMERIC(18,0)
	);

IF OBJECT_ID('tempdb..#clc','U') IS NOT NULL
	BEGIN
		DROP TABLE #clc
	END

	CREATE TABLE #clc (
		  number	VARCHAR(8)	
		 ,loc		VARCHAR(8)
		 ,class		VARCHAR(2)
	);

/*** FETCH FBOP INMATES/INSUREDS NOT YET IN LCS ***/
INSERT INTO #insureds (
	 insuredID
)

	SELECT DISTINCT		pid.pol_insrd_dtl_insrd_id	[pid_insuredID]
	
	FROM	adminsys.dbo.policy_insured_detail [pid]
		INNER JOIN	adminsys.dbo.policy_master [pm]
			ON	pid.pol_insrd_dtl_cert_nbr = pm.pol_mst_cert_nbr
				AND		pid.pol_insrd_dtl_seq_nbr	= pm.pol_mst_seq_nbr
				AND		pm.pol_mst_prod_cd			= 'ACFBP'
		INNER JOIN	adminsys.dbo.product_lcs_source		[pls]
			ON	pm.pol_mst_prod_cd	=	pls.prod_cd
		LEFT JOIN	adminsys.dbo.lcs_link	[ll]
			ON	pid.pol_insrd_dtl_insrd_id = ll.adminsys_insured_id

	WHERE	ll.adminsys_insured_id IS NULL

/*** FETCH STATIC CLIENT NUMBER, LOCATION, CLASS ***/
INSERT INTO #clc (
	 number
	,loc
	,class
)
	SELECT c.number
		  ,c.location
		  ,c.class
	FROM LCS_SQL.dbo.Client [c]
		INNER JOIN LCS_SQL.dbo.claim_source	[cs]
			ON	c.[source] = cs.claim_source_id
				AND	cs.claim_source_link = 'FBOP'

SET @li_error = @@ERROR
IF @li_error != 0
	BEGIN
		SET @li_return = -1000
		SET	@li_raiserror_ind = 1
		SET @ls_error_message = 'Error fetching new insureds for new coverage information'
		GOTO Procedure_Exit
	END;



/*** ADD INSURED RECORD FOR NEW INMATES  ***/
INSERT INTO LCS_SQL.dbo.EligibilityInsured (
	 [source]
	,employeeID
	,familyMemberID
	,lastName
	,firstName
	,AddressLine1
	,AddressLine2
	,City
	,[State]
	,PostalCode
	,CountryCode
	,dateOfBirth
	,PatientEligibility
	,gender
	,relationshipCode
	,dateOfHire
	,clientNumber
	,clientLocation
	,ClientClass
	,dateEffective
	,DateTermination
	,PerCauseIndicator
	,CreateBy
)
	SELECT DISTINCT (SELECT cs.claim_source_id
			FROM LCS_SQL.dbo.claim_source [cs]
			WHERE cs.claim_source_link = 'FBOP')
		  ,RIGHT(REPLICATE('0',9) + CAST(pid.pol_insrd_dtl_insrd_id AS VARCHAR(9)),9)
		  ,'A'
		  ,adminsys.dbo.fn_name_format(im.insrd_mst_name,'L','U')
		  ,adminsys.dbo.fn_name_format(im.insrd_mst_name,'F','U')
		  ,el.address1
		  ,el.address2
		  ,el.city
		  ,el.[state]
		  ,el.zip
		  ,CASE
				WHEN el.country='USA' THEN 'US'
				ELSE 'XX'
		   END
		  ,im.insrd_mst_dob
		  ,'01'
		  ,im.insrd_mst_gender
		  ,'SE'
		  ,pid.pol_insrd_dtl_effect_dt
		  ,(SELECT ca.code
			FROM LCS_SQL.dbo.ClientAdministration [ca]
			WHERE ca.clientName = 'FBOP FCI OTISVILLE')
		  ,pm.certificateNumber
		  ,'01'
		  ,pid.pol_insrd_dtl_effect_dt
		  ,pid.pol_insrd_dtl_expire_dt
		  ,0
		  ,'UCSLOAD'
	FROM #insureds [i]
		INNER JOIN adminsys.dbo.insured_master [im]
			ON i.insuredID = im.insrd_mst_id
		INNER JOIN adminsys.dbo.policy_insured_detail [pid]
			ON im.insrd_mst_id = pid.pol_insrd_dtl_insrd_id
		INNER JOIN adminsys.dbo.policy_master [pm]
			ON pid.pol_insrd_dtl_cert_nbr = pm.pol_mst_cert_nbr
		INNER JOIN adminsys.temp.temp_Dynamo_Adminsys_EligibilityLoad [el]
			ON el.extID = pid.pol_insrd_dtl_ext_id

SET @li_error = @@ERROR
IF @li_error != 0
	BEGIN
		SET @li_return = -1000
		SET	@li_raiserror_ind = 1
		SET @ls_error_message = 'Error INSERTing to EligibilityInsured'
		GOTO Procedure_Exit
	END;


/*** CREATE UNIQUEID LINK FOR NEW INMATES ***/
INSERT INTO LCS_SQL.dbo.EligibilityUniqueID (
	 [source]
	,employeeID
	,uniqueID
	,createBy
)
	SELECT DISTINCT (SELECT cs.claim_source_id
					 FROM LCS_SQL.dbo.claim_source [cs]
					 WHERE cs.claim_source_link = 'FBOP')
					 ,RIGHT(REPLICATE('0',9) + CAST(im.insrd_mst_id AS VARCHAR(9)),9)
					 ,a.pol_insrd_dtl_ext_id
					 ,'UCSLOAD'
	FROM adminsys.dbo.insured_master [im]
		INNER JOIN #insureds [i]
			ON im.insrd_mst_id = i.insuredID
		OUTER APPLY (
			SELECT DISTINCT pid.pol_insrd_dtl_ext_id
			FROM adminsys.dbo.policy_insured_detail [pid]
			WHERE i.insuredID = pid.pol_insrd_dtl_insrd_id
		) a

SET @li_error = @@ERROR
IF @li_error != 0
	BEGIN
		SET @li_return = -1000
		SET	@li_raiserror_ind = 1
		SET @ls_error_message = 'Error INSERTing to EligibilityUniqueID'
		GOTO Procedure_Exit
	END;


/*** LINK LCS INSURED TO ADMINSYS INSURED ***/
INSERT INTO adminsys.dbo.lcs_link (
	 adminsys_insured_id
	,lcs_person
	,lcs_source
	,[manual]
	,create_date
	,create_by
)
	SELECT DISTINCT i.insuredID
					,RIGHT(REPLICATE('0',9) + CAST(i.insuredID AS VARCHAR(9)),9)+'A'
					,'FBOP'
					,'N'
					,GETDATE()
					,'UCSLOAD'
	FROM #insureds [i]

SET @li_error = @@ERROR
IF @li_error != 0
	BEGIN
		SET @li_return = -1000
		SET	@li_raiserror_ind = 1
		SET @ls_error_message = 'Error INSERTing to lcs_link'
		GOTO Procedure_Exit
	END;


/*** CREATE CLIENT ASSIGNMENT RECORD ***/
INSERT INTO LCS_SQL.dbo.EligibilityClientAssignment (
	 [source]
	,employeeID
	,familyMemberID
	,keyDate
	,EffectiveDate
	,ClientNumber
	,ClientLocation
	,ClientClass
	,createBy
)

	SELECT DISTINCT (SELECT cs.claim_source_id
					 FROM LCS_SQL.dbo.claim_source [cs]
					 WHERE cs.claim_source_link = 'FBOP')
					,RIGHT(REPLICATE('0',9) + CAST(im.insrd_mst_id AS VARCHAR(9)),9)
					,'A'
					,CAST(99999999-(CAST(CAST(DATEPART(yyyy,pid.pol_insrd_dtl_effect_dt) AS CHAR(4))+RIGHT('00'+LTRIM(RTRIM(CAST(DATEPART(mm,pid.pol_insrd_dtl_effect_dt) AS NCHAR(2)))),2)+RIGHT('00'+LTRIM(RTRIM(CAST(DATEPART(dd,pid.pol_insrd_dtl_effect_dt) AS NCHAR(2)))),2) AS INT)) AS NCHAR(8))
					,pid.pol_insrd_dtl_effect_dt
					,a.number
					,a.loc
					,a.class
					,'UCSLOAD'
	FROM adminsys.dbo.insured_master [im]
		INNER JOIN #insureds [i]
			ON im.insrd_mst_id = i.insuredID
		INNER JOIN adminsys.dbo.policy_insured_detail [pid]
			ON i.insuredID = pid.pol_insrd_dtl_insrd_id
		OUTER APPLY (SELECT number, loc, class
					 FROM #clc) a

SET @li_error = @@ERROR
IF @li_error != 0
	BEGIN
		SET @li_return = -1000
		SET	@li_raiserror_ind = 1
		SET @ls_error_message = 'Error INSERTing to EligibilityClientAssignment'
		GOTO Procedure_Exit
	END;


/*** CREATE COVERAGE ASSIGNMENT RECORD ***/
INSERT INTO LCS_SQL.dbo.EligibilityCoverageAssignment (
	 [Source]
	,EmployeeId
	,FamilyMemberId
	,GeneralCoverage
	,KeyDate
	,AmountVolume
	,PatientEligibility
	,EffectiveDate
	,TerminationDate
	,PrintHipaa
	,AutoAdjustmentIndicator
	,CreditableCoverage
	,SecondaryCob
	,SecondaryMedicare
	,DenyAutoAdjudication
	,CreateBy
	,CreateDate
)

	SELECT DISTINCT (SELECT cs.claim_source_id
					 FROM LCS_SQL.dbo.claim_source [cs]
					 WHERE cs.claim_source_link = 'FBOP')
					 ,RIGHT(REPLICATE('0',9) + CAST(im.insrd_mst_id AS VARCHAR(9)),9)
					 ,'A'
					 ,'01'
					 ,CAST(99999999-(CAST(CAST(DATEPART(yyyy,pid.pol_insrd_dtl_effect_dt) AS CHAR(4))+RIGHT('00'+LTRIM(RTRIM(CAST(DATEPART(mm,pid.pol_insrd_dtl_effect_dt) AS NCHAR(2)))),2)+RIGHT('00'+LTRIM(RTRIM(CAST(DATEPART(dd,pid.pol_insrd_dtl_effect_dt) AS NCHAR(2)))),2) AS INT)) AS NCHAR(8))
					 ,NULL
					 ,'01'
					 ,pid.pol_insrd_dtl_effect_dt
					 ,pid.pol_insrd_dtl_expire_dt
					 ,NULL
					 ,'N'
					 ,NULL
					 ,'N'
					 ,'N'
					 ,'N'
					 ,'UCSLOAD'
					 ,GETDATE()
	FROM adminsys.dbo.insured_master [im]
		INNER JOIN #insureds [i]
			ON im.insrd_mst_id = i.insuredID
		INNER JOIN adminsys.dbo.policy_insured_detail [pid]
			ON im.insrd_mst_id = pid.pol_insrd_dtl_insrd_id

SET @li_error = @@ERROR
IF @li_error != 0
	BEGIN
		SET @li_return = -1000
		SET	@li_raiserror_ind = 1
		SET @ls_error_message = 'Error INSERTing to EligibilityCoverageAssignment'
		GOTO Procedure_Exit
	END;


/*** CREATE CLAIM AUTHORIZATION RECORD ***/
INSERT INTO LCS_SQL.dbo.ClaimAuthorization (
	 FormID
	,ClaimAuthorizationTypeID
	,Claim_SourceID
	,Ssn_Passport
	,EmployeeID
	,PrisonFacility
	,YRegNum
	,ApptRequestDate
	,ApptScheduleDate
	,ApptOccuredDate
	,InmateName
	,InmateGender
	,InmateDOB
	,ApptType
	,ProviderInfo
	,ApptReason
)

	SELECT DISTINCT SUBSTRING(LTRIM(RTRIM(el.AppointmentNumber)),1,20)
					,(SELECT cat.ID
						FROM LCS_SQL.dbo.ClaimAuthorizationType [cat]
						WHERE cat.FileType = 'FBOP')
					,(SELECT cs.claim_source_id
						FROM LCS_SQL.dbo.claim_source [cs]
						WHERE cs.claim_source_link = 'FBOP')
					,SUBSTRING(LTRIM(RTRIM(el.extID)),1,30)
					,RIGHT(REPLICATE('0',9) + CAST(pid.pol_insrd_dtl_insrd_id AS VARCHAR(9)),9)
					,SUBSTRING(LTRIM(RTRIM(el.Prison)),1,80)
					,SUBSTRING(LTRIM(RTRIM(el.YRegNumber)),1,20)
					,el.DateAppointmentRequested
					,el.DateAppointmentScheduled
					,el.DateAppointmentScheduled
					,SUBSTRING(LTRIM(RTRIM(el.lName+', '+el.fName)),1,100)
					,CASE
							WHEN LTRIM(RTRIM(el.gender)) = ''
							THEN 'U'

							ELSE SUBSTRING(LTRIM(RTRIM(el.gender)),1,1)
					 END
					,el.dob
					,SUBSTRING(LTRIM(RTRIM(el.AppointmentType)),1,100)
					,SUBSTRING(LTRIM(RTRIM(el.FacilityName)),1,100)
					,SUBSTRING(LTRIM(RTRIM(el.ReasonForAppointment)),1,100)
	FROM adminsys.temp.temp_Dynamo_Adminsys_EligibilityLoad [el]
		INNER JOIN adminsys.dbo.policy_insured_detail [pid]
			ON pid.pol_insrd_dtl_ext_id = el.extID
				AND el.LCSLoad = 0
	WHERE el.AppointmentNumber NOT IN (
			SELECT el.AppointmentNumber
			FROM adminsys.temp.temp_Dynamo_Adminsys_EligibilityLoad [el]
				INNER JOIN LCS_SQL.dbo.ClaimAuthorization [ca]
					ON el.AppointmentNumber = ca.FormID
						AND ca.ClaimAuthorizationTypeId = (
							SELECT cat.ID
							FROM LCS_SQL.dbo.ClaimAuthorizationType [cat]
							WHERE cat.FileType = 'FBOP'
						)
		)

SET @li_error = @@ERROR
IF @li_error != 0
	BEGIN
		SET @li_return = -1000
		SET	@li_raiserror_ind = 1
		SET @ls_error_message = 'Error INSERTing to ClaimAuthorization'
		GOTO Procedure_Exit
	END;

DROP TABLE #insureds
DROP TABLE #clc

/*** UPDATE INSERT LOG ***/
DECLARE @catID VARCHAR(4)

SELECT @catID = cat.ID 
FROM LCS_SQL.dbo.ClaimAuthorizationType [cat]
WHERE cat.FileType = 'FBOP'

UPDATE [el]
SET LCSload = 1
FROM adminsys.temp.temp_Dynamo_Adminsys_EligibilityLoad [el]
WHERE el.LCSload=0
	AND el.AppointmentNumber+@catID IN (
		SELECT DISTINCT formID+CAST(ClaimAuthorizationTypeID AS VARCHAR(4))
		FROM LCS_SQL.dbo.ClaimAuthorization
		WHERE el.AppointmentNumber+@catID = formID+CAST(ClaimAuthorizationTypeID AS VARCHAR(4))
	)

/*** IF ALL ELSE FAILS, ABANDON SHIP ***/
Procedure_Exit:



IF (@li_begin_tran_ind = 1 AND @li_error = 0)	/*** transaction open and no rollback ***/
BEGIN
     COMMIT TRAN

     SET @li_error = @@ERROR
     IF  (
         @li_error <> 0 
         OR @@TRANCOUNT <> 0
         )
     BEGIN
          SET @li_raiserror_ind   = 1
          SET @ls_error_message   = 'COMMIT TRAN failed in ' + @lvc_procedure_name + '.'
     END
END

-- ROLLBACK TRAN if the transaction was created in this procedure and there
-- was an error

IF (@li_begin_tran_ind = 1 AND @li_error <> 0)		/*** rollback entire transaction if any errs raised ***/
   ROLLBACK TRAN

IF @li_raiserror_ind <> 0		/*** raise error as necessary ***/
BEGIN
	RAISERROR 
	(
		@ls_error_message,	-- Message text
		16,					-- Severity
		1					-- State
	);
END

RETURN @li_return

SET NOCOUNT OFF

