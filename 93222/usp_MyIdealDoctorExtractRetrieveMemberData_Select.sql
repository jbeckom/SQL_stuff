USE [adminsys];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE [dbo].[usp_MyIdealDoctorExtractRetrieveMemberData_Select]

AS
/*******************************************************************************
Object:		dbo.usp_MyIdealDoctorExtractRetrieveMemberData_Select

Arguments:	none

Description: Retrieve Member Data for MyIdealDoctorExtract
International Medical Group

Revision History:

Date        Project		Author          Comments
2018/01/18	93222		Josh Beckom		Create

*******************************************************************************/

SET NOCOUNT ON

DECLARE	@ls_error_message				VARCHAR(255)	-- local variable to set the error text when raising error
		,@lvc_procedure_name			SYSNAME			-- procedure name
		,@li_begin_tran_ind				TINYINT			-- Transaction indicator (0 No BEGIN TRAN executed, 1 BEGIN TRAN executed)
		,@li_raiserror_ind				TINYINT			-- Raise Error indicator (0 Do NOT call RAISERROR, 1 Do call RAISERROR)
		,@li_rowcount					INT				-- Local variable to store @@ROWCOUNT after INSERT/UPDATE
		,@li_error						INT				-- Local variable to save @@ERROR
		,@ai_override_tran_management	TINYINT
		,@li_return						INT

/************************************
	SET THE STORED PROCEDURE NAME
************************************/
SET @lvc_procedure_name = 'dbo.usp_MyIdealDoctorExtractRetrieveMemberData_Select'

SET @li_return = 0

/******************************
	TRANSACTION MANAGEMENT
******************************/
SET @li_raiserror_ind = 0
SET @li_begin_tran_ind = 0
SET @li_rowcount = NULL
SET @ls_error_message = ''
SET @li_error = 0
SET @ai_override_tran_management = 0;

IF @ai_override_tran_management = 0
OR @ai_override_tran_management IS NULL
BEGIN
     -- Ensure that @@TRANCOUNT is currently valid (0 or 1)
     IF @@TRANCOUNT NOT IN (0,1)
     BEGIN 
          -- @@TRANCOUNT is invalid.
          SET @li_begin_tran_ind    = 0
          SET @li_raiserror_ind     = 1
          SET @ls_error_message      
              = 'Invalid @@TRANCOUNT ( ' + CONVERT(char(4), @@TRANCOUNT )+ ' ) in ' + @lvc_procedure_name + '.'
          GOTO Procedure_Exit
     END 
     
     -- @@TRANCOUNT is valid.  Determine if there is already an open transaction
     IF @@TRANCOUNT = 1
     BEGIN 
          -- There is already an open transaction.  Ride it.  Don't open a nested transaction.
          SET @li_begin_tran_ind = 0
     END
     ELSE
     BEGIN
          -- There is no open transaction.  Begin one.
          BEGIN TRAN
          
          SET @li_error = @@ERROR
          -- Check to see if the BEGIN TRAN was successful.
          IF (
             @li_error <> 0 
             OR @@TRANCOUNT <> 1
             )
          BEGIN
               -- BEGIN TRAN failed.
               SET @li_begin_tran_ind         = 0
               SET @li_raiserror_ind          = 1
               SET @ls_error_message          = 'BEGIN TRAN failed in ' + @lvc_procedure_name + '.'
               GOTO Procedure_Exit
          END
          ELSE
               -- BEGIN TRAN was successful. 
               SET @li_begin_tran_ind = 1
     END
END -- override

/*****************************************
	START STORED PROCEDURE PROCESSING
*****************************************/
SELECT	'Individual Plan'								AS PlanOption
		,'Primary'										AS MemberType
		,''												AS MemberEmail
		,im.insrd_mst_first_name						AS FirstName
		,im.insrd_mst_last_name							AS LastName
		,''												AS HomePhone
		,''												AS CellPhone
		,COALESCE(im.insrd_mst_gender, 'U')				AS insrd_mst_gender
		,CONVERT(VARCHAR(10),im.insrd_mst_dob,101)		AS DateOfBirth
		,'2960 N Meridian St'							AS Address1
		,''												AS Address2
		,'Indianapolis'									AS City
		,'IN'											AS StateCode
		,'46208'										AS Zip
		,CASE (midde.prod_cd)
			WHEN 'AVHBP'	THEN 'MYIDR1356'
			WHEN 'AVHCA'	THEN 'MYIDR1357'
			WHEN 'NCCC'		THEN 'MYIDR1132'
			WHEN 'FEMA'		THEN 'MYIDR1132'
		 ELSE NULL
		 END											AS GroupID
		,im.insrd_mst_id								AS OtherMemberID
		,midde.ActiveIndicator							AS [Status]
		,RIGHT(REPLICATE('0',8)+LTRIM(midde.ext_id),8)	AS [UniqueIdentifier]

FROM	dbo.MyIDealDoctorExtract	AS midde
	INNER JOIN	dbo.insured_master	AS im
		ON	midde.InsuredID	= im.insrd_mst_id



SET @li_error = @@ERROR
IF @li_error <> 0 
BEGIN
     SET @li_return = -1000
     SET @li_raiserror_ind = 1
     SET @ls_error_message = 'ERROR retrieving member data'
     GOTO Procedure_Exit
END;

/************
	EXIT
************/

Procedure_Exit:


-- COMMIT if this procedure opened a transaction and the rollback ind is not set
IF (
   @li_begin_tran_ind = 1 
   AND @li_error = 0
   )
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

IF (
   @li_begin_tran_ind = 1 
   AND @li_error <> 0
   )
   ROLLBACK TRAN

-- RAISERROR if necessary
IF @li_raiserror_ind <> 0
BEGIN
	RAISERROR 
	(
		@ls_error_message,  -- Message text.
		16,   -- Severity.
		1     -- State.
	);
END

RETURN @li_return

SET NOCOUNT OFF

