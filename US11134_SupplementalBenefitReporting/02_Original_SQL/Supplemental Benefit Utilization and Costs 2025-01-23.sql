use [Medicare_Custom]
go

set transaction isolation level read uncommitted
go


set nocount off

-- Variables to set
declare @FULL_UPDATE char(1) = 'Y'
declare @FINAL_QUERY_ONLY char(1) = 'N'
declare @UPDATE_ELIGIBLE_MEMBERS char(1) = 'N'
declare @GENERATE_FILES char(1) = 'N'
declare @USE_FILE_HEADERS char(1) = 'N'
declare @AGGREGATE_PBPS char(1) = 'Y'
declare @UPDATE_PMPM char(1) = 'Y'
declare @UPDATE_USAGE_BASED char(1) = 'N'

-- Internal variables
declare @NOW datetime = getdate()
declare @DATASOURCE varchar(30) 
--declare @TARGET_TABLE varchar(100) = 'Bene_Members'  -- Bene_Claims
--declare @DATA_SOURCE varchar(100) = 'QNXT_CLM'
declare @ROUNDED_TIMESTAMP datetime = datetimefromparts(datepart(year, getdate()), datepart(month, getdate()), datepart(day, getdate()), datepart(hour, getdate()), 0, 0, 0)
declare @FOREVER date = '2078-12-31'
declare @REPORTING_YEAR int = 2025
declare @START_DATE	date = datefromparts(@REPORTING_YEAR,  1,  1)
declare @START_DATE_STR8 char(8) = format(@START_DATE, 'yyyyMMdd')
declare @START_DATE_STR_AMPM varchar(20) = format(@START_DATE, 'M/d/yyyy h:mm:ss tt')
declare @END_DATE		date = datefromparts(@REPORTING_YEAR, 12, 31)
declare @END_DATE_STR8 char(8) = format(@END_DATE, 'yyyyMMdd')
declare @END_DATE_STR_AMPM varchar(20) = format(@END_DATE, 'M/d/yyyy h:mm:ss tt')
declare @MSG varchar(1000) = ''

declare @Months table ([MonthStart] date not null primary key)
; with [cteMonths] ([MonthStart])
as  
(
	select @START_DATE [MonthStart]
	union all
	select dateadd(month, 1, [cteMonths].[MonthStart]) [MonthStart]
	from [cteMonths]
	where dateadd(month, 1, [cteMonths].[MonthStart]) < @END_DATE
)
insert @Months ( [MonthStart] ) select [MonthStart] from [cteMonths]



if @FINAL_QUERY_ONLY = 'Y' goto FINAL_QUERY

set nocount off

-- Load QNXT Benefits to SBSC Code table .. ------------------------------------------------------------
-- drop table if exists CMSReporting.QNXT_Benefits_2025
if OBJECT_ID('tempdb..CMSReporting.QNXT_Benefits_2025') is null 

if ( 0 = ( select count(1) from CMSReporting.QNXT_Benefits_2025 ) )
begin
	
	raiserror('Loading #Benefits temp table ..', 0, 1 ) with nowait;
	drop table if exists #Benefit
	select distinct trim(isnull(UBID.value,'')) [SBSC], right(rtrim(description),4) [NetStatus], * 
	into #Benefit
	from Plandata_Prod.dbo.Benefit bene 
	outer apply ( select value from string_split(bene.UBID, '_') where  rtrim(isnull(bene.UBID, '')) != '' )[ubid]
	where EffDate <= @END_DATE
	and   TermDate >= @START_DATE
	update #Benefit set TermDate = @FOREVER where TermDate is null
	create index ix_PlanID_EffDate_TermDate_SBSC_NetStatus on #Benefit (PlanID, SBSC, NetStatus, EffDate, TermDate)

	raiserror('Trimming #Benefits temp table ..', 0, 1 ) with nowait;
	delete 
	from  #Benefit 
	where not ( [SBSC] != '' or [NetStatus] = ' OON' )

	update #Benefit  set [NetStatus] = 'OON' where [NetStatus] = ' OON'

	raiserror('Deleting OON #Benefits having SBSC ..', 0, 1 ) with nowait;
	delete from beneoon
	from #Benefit bene
	join #Benefit beneoon on beneoon.planid = bene.planid
												and beneoon.benefitid = bene.benefitid
												and beneoon.NetStatus = 'OON'
	where bene.SBSC != ''

	select 'ALL' [Query], count(1) from #Benefit
	select 'OON 1' [Query], count(1) from #Benefit where [NetStatus] = 'OON'

	--update #Benefit set SBSC = 'OON'  where [NetStatus] = 'OON' and rtrim(isnull(SBSC,'')) = ''
	     


	--select bene.SBSC,  count(1) [Rows]
	--from #Benefit bene
	--where bene.SBSC in ('7B1', '7F', '13A', '14B', '14c12', '4c1', '4c2') 	
	--group by bene.SBSC
	--order by bene.SBSC

	--goto THE_END

--select * from PHP_EDW.INFORMATION_SCHEMA.columns where column_name like '%benefit%' and column_name like '%id%' and column_name not like '%plan%' order by table_name

	truncate table Medicare_Custom.CMSReporting.QNXT_Benefits_2026

	raiserror('Loading CMSReporting.QNXT_Benefits_2025 by UBID ..', 0, 1 ) with nowait;

	insert into CMSReporting.QNXT_Benefits_2026
	select op.OrgPolicyId, rtrim(pp.rateid) [RateId]
			, pp.planid [PlanId]
			, isnull(rtrim(bsrv.svcmin), '') [MinProcCode], isnull(rtrim(bsrv.svcmax), '') [MaxProcCode], rtrim(bene.BenefitID) [BenefitID]
			, isnull(bsrv.Category, 'BEN') [Type]
			, op.PolicyNum
			, bene.SBSC [SBSC_Code] 
	--into CMSReporting.QNXT_Benefits_2025
	from Plandata_Prod.dbo.orgpolicy [op] 
	join Plandata_Prod.dbo.policyplans [pp] on pp.polid = op.polid
	join PHP_EDW.[dbo].[vwLineOfBusinessByPlan]	lob on lob.planid = pp.planid
	and lob.LOB = 'Medicare Advantage'
	join Plandata_Prod.dbo.benefitplan [bp] on bp.planid = pp.planid																		
	join #Benefit [bene] on bene.PlanID = bp.PlanId
	and bene.EffDate <= @END_DATE
	and bene.TermDate >= @START_DATE
	and bene.SBSC != ''																			
	left join Plandata_Prod.dbo.beneservice [bsrv] on bsrv.benefitid = bene.benefitid
	and bsrv.planid = bp.planid
	--cross apply string_split(bene.SBSC, '_') [ubid]

	where op.effdate >= @START_DATE

	group by op.OrgPolicyId, rtrim(pp.rateid) 
			, pp.planid 
			, isnull(rtrim(bsrv.svcmin), '') , isnull(rtrim(bsrv.svcmax), '') , rtrim(bene.BenefitID) 
			, isnull(bsrv.Category, 'BEN') 
			, op.PolicyNum
			, bene.SBSC
	order by [OrgPolicyId], [RateId], rtrim(bene.BenefitID), 
	[Type], [SBSC_Code], pp.planid, isnull(rtrim(bsrv.svcmin), ''), isnull(rtrim(bsrv.svcmax), '')

	select 'ALL 2' [Query], count(1) from CMSReporting.QNXT_Benefits_2025
	-- order by op.OrgPolicyId, [MinProcCode], [MaxProcCode], [Type], [SBSC_Code]

	--raiserror('Indexing CMSReporting.QNXT_Benefits_2025 by UBID ..', 0, 1 ) with nowait;

	--alter table CMSReporting.QNXT_Benefits_2025 alter column [OrgPolicyId] varchar(15) not null 
	--alter table CMSReporting.QNXT_Benefits_2025 alter column [RateId] varchar(15) not null 
	--alter table CMSReporting.QNXT_Benefits_2025 alter column [PlanId] varchar(15) not null 
	----alter table CMSReporting.QNXT_Benefits_2025 alter column [PolicyNumd] varchar(15) not null 
	--alter table CMSReporting.QNXT_Benefits_2025 alter column [MinProcCode] varchar(6) not null
	--alter table CMSReporting.QNXT_Benefits_2025 alter column [MaxProcCode] varchar(6) not null
	--alter table CMSReporting.QNXT_Benefits_2025 alter column [BenefitId] varchar(15) not null
	--alter table CMSReporting.QNXT_Benefits_2025 alter column [Type] varchar(3) not null`
	--alter table CMSReporting.QNXT_Benefits_2025 alter column [SBSC_Code] varchar(10) not null

	--  SELECT name FROM tempdb.sys.key_constraints WHERE type = 'PK' AND OBJECT_NAME(parent_object_id) = N'CMSReporting.QNXT_Benefits_2025';
	--	alter table CMSReporting.QNXT_Benefits_2025 drop constraint [PK__##QNXT_B__B81A748F99A7E742]
	-- 	alter table CMSReporting.QNXT_Benefits_2025 add primary key clustered ([OrgPolicyId], [RateId], [BenefitId], [Type], [SBSC_Code], [PlanId], [MinProcCode], [MaxProcCode])
	--	create index ix_tmp_QNXT_Benefits_2025_OrgPolicyId_RateId_BenefitId on CMSReporting.QNXT_Benefits_2025 ([OrgPolicyId], [RateId], [PlanId], [BenefitId])
		--create index ix_tmp_QNXT_Benefits_2025_OrgPolicyId_RateId_BenefitId on CMSReporting.QNXT_Benefits_2025 ([OrgPolicyId], [RateId], [PlanId], [BenefitId])

	raiserror('Loading CMSReporting.QNXT_Benefits_2025 for OON ..', 0, 1 ) with nowait;
	insert 	into CMSReporting.QNXT_Benefits_2026 with (TABLOCK)
		select op.OrgPolicyId, rtrim(pp.rateid) [RateId]
			, pp.planid
			, isnull(rtrim(bsrv.svcmin), '') [MinProcCode], isnull(rtrim(bsrv.svcmax), '') [MaxProcCode], rtrim(bene.BenefitID) [BenefitID]
			, 'OON' [Type]
			, op.PolicyNum
			, 'OON' [SBSC_Code] 

	from Plandata_Prod.dbo.orgpolicy [op] 
	join Plandata_Prod.dbo.policyplans [pp] on pp.polid = op.polid
  join PHP_EDW.[dbo].[vwLineOfBusinessByPlan]	lob on lob.planid = pp.planid
		and lob.LOB = 'Medicare Advantage'																							
	join Plandata_Prod.dbo.benefitplan [bp] on bp.planid = pp.planid					
	join #Benefit [bene]	 on bene.PlanID = bp.PlanId
	--and bene.EffDate <= @END_DATE
	--and bene.TermDate >= @START_DATE
	and rtrim(isnull(bene.SBSC, '')) = ''
	and bene.NetStatus = 'OON' 

	left join Plandata_Prod.dbo.beneservice [bsrv] on bsrv.benefitid = bene.benefitid
and bsrv.planid = bp.planid
														

	where op.effdate >= @START_DATE
	  --and bsrv.benefitid is null

	group by op.OrgPolicyId, rtrim(pp.rateid), pp.planid, rtrim(bsrv.svcmin), rtrim(bsrv.svcmax), rtrim(bene.BenefitID)
				 , op.PolicyNum

  order by [OrgPolicyId], [RateId], [BenefitId], [Type], [SBSC_Code], [PlanId], [MinProcCode], [MaxProcCode]
   
	-- order by op.OrgPolicyId, [MinProcCode], [MaxProcCode], [Type], [SBSC_Code]

	set nocount off

	select 'OON 2' [Query], count(1) from CMSReporting.QNXT_Benefits_2025 where [SBSC_Code] = 'OON'

	drop table if exists #Benefit

end -- OBJECT_ID('tempdb..CMSReporting.QNXT_Benefits_2025') is null 



--------------------------------------------------------------------------------------------------------
-- Initialize CMSReporting.SupplementalBenefitUtilizationAndCosts table --------------------------------

--delete from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026
--where ( [Contract] = 'H5945' and [PBP] in ('003','004','005','006') )
--   or  ( [Contract] = 'H7680' and [PBP] in ('003','004','005','006') )



if ( @FULL_UPDATE = 'Y' )
begin
	delete from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026

	insert Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 
		(	[Contract], [PBP]
		, [PBP Category], [SB Name], [How is the SB offered?], [Unit of utilization used by Plan] 
		, [The number of enrollees eligible]
		, [The number of enrollees who utilized benefit once]
		, [The total instances of utilization among eligible enrollees]
		, [The median number of utilizations among enrollees who utilized the benefit at least once]
		, [The total net amount incurred by plan to offer the benefit]
		, [The type of payment arrangement(s) the plan used to implement the benefit]
		, [How the plan accounts for the cost of the benefit]
		, [The total out-of-pocket-cost per utilization for enrollees]
		, [The median out-of-pocket cost for enrollees]
		, [Sort1], [SBSC_Code], [LastUpdate]
		)

	select  [plan].[Contract], [plan].[PBP]
				, [sbsc].[SBSC_BaseCode], [sbsc].[SupplementalBenefitDescription], [sbsc].[HowOffered], [sbsc].[UtilizationUnit]
				, 0 [The number of enrollees eligible]
				, 0 [The number of enrollees who utilized benefit once]
				, 0 [The total instances of utilization among eligible enrollees]
				, 0 [The median number of utilizations among enrollees who utilized the benefit at least once]
				, 0 [The total net amount incurred by plan to offer the benefit]
				, sbsc.TypeOfPaymentArrangements [The type of payment arrangement(s) the plan used to implement the benefit]
				, sbsc.HowAreCostsAccounted [How the plan accounts for the cost of the benefit]
				, 0 [The total out-of-pocket-cost per utilization for enrollees]
				, 0 [The median out-of-pocket cost for enrollees]
				, sort1.val, [SBSC_Code], @NOW
	from [CMSReporting].[SBSC_Code] [sbsc]
	cross apply ( select case when isnumeric(left([SBSC_BaseCode], 1)) = 0 then 9999
		else convert(int, left([SBSC_BaseCode], case	when len([SBSC_BaseCode])=1 then 1
					when charindex('-',left([SBSC_BaseCode], 2)) > 0 and isnumeric(left([SBSC_BaseCode], 2)) = 1 then 2   
					else 1
		end
		)
		)
		end [val] ) [sort1]

	cross apply ( select left(PolicyNum, 5) [Contract], substring(PolicyNum, 6, 3) [PBP] 
								from plandata_prod.dbo.Policy pol 
								join PHP_EDW.dbo.vwLineOfBusinessByProgram pgm on pgm.ProgramId = pol.programid 
								and LOB = 'Medicare Advantage'
								where effdate <= @END_DATE
								--and PolicyNum not in (	'H5945003', 'H5945004', 'H5945005', 'H5945006'
								--					, 'H7680003', 'H7680004', 'H7680005', 'H7680006' )
								group by left(PolicyNum, 5), substring(PolicyNum, 6, 3)
								union
								select 'H5945' [Contract], '801' [PBP] 
								union
								select 'H5945' [Contract], '802' [PBP] 
								union
								select 'H5945' [Contract], '804' [PBP] 
								union
								select 'H5945' [Contract], '805' [PBP] 
								union
								select 'H7680' [Contract], '801' [PBP] 

							) [plan]

	--cross apply ( select left(PlanDesc, 5) [Contract], substring(PlanDesc, 7, 3) [PBP] 
	--							from PHP_EDW.[Medicare].MemberEnrollDetails
	--							where 1=1
	--							  	and EnrollEffDate <= @END_DATE
	--								and EnrollTermDate >= @START_DATE
	--								and EnrollTermDate > EnrollEffDate
	--							group by left(PlanDesc, 5), substring(PlanDesc, 7, 3)
	--						) [plan]
	
	group by [plan].[Contract], [plan].[PBP], sort1.val, [SBSC_BaseCode], [SBSC_Code], [SupplementalBenefitDescription], [HowOffered], UtilizationUnit
				, sbsc.TypeOfPaymentArrangements, sbsc.HowAreCostsAccounted 
	order by [Contract], sort1.val, [SBSC_BaseCode], [sbsc].[SBSC_Code], [SupplementalBenefitDescription]

end

set nocount on



-----------------------------------------------------------------------------------------------------
-- Update [The number of enrollees eligible] & [The number of enrollees who utilized benefit once] ---------------------------------------

if @UPDATE_ELIGIBLE_MEMBERS != 'Y' goto UPDATE_PMPM

-- Several benefits are available to all MA members, so query that count here.
declare @TOTAL_MA_ELIGIBLE_MEMBERS table 
	(   [PolicyNum] char(8) not null, [Members] int,  primary key clustered ([PolicyNum])
	  , [Contract] as left([PolicyNum], 5) persisted, [PBP] as substring([PolicyNum], 6, 3) persisted
	)
insert @TOTAL_MA_ELIGIBLE_MEMBERS ([PolicyNum], [Members])
 select [PolicyNum], count(distinct MemberID) [Members]
from [PHP_EDW].[Master].MedicalEnrollAll enrl
where 1=1
	and [Type] = 'Medicare Advantage'
	and EffDate <= @END_DATE
	and isnull(TermDate, @FOREVER) >= @START_DATE  
	and TermDate > EffDate
	group by [PolicyNum]
order by left([PolicyNum],5), substring([PolicyNum],6,3)
--SELECT * FROM @TOTAL_MA_ELIGIBLE_MEMBERS
UPDATE supp
   SET [The number of enrollees eligible] = mem.Members
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
JOIN @TOTAL_MA_ELIGIBLE_MEMBERS mem  ON supp.Contract = mem.Contract AND supp.PBP = mem.PBP

declare @TOTAL_MA_ELIGIBLE_MEMBERS_BY_MONTH table 
	(   [PolicyNum] char(8) not null, [MonthStart] date not null, [Members] int,  primary key clustered ([PolicyNum], [MonthStart]) 
	  , [Contract] as left([PolicyNum], 5) persisted, [PBP] as substring([PolicyNum], 6, 3) persisted
	)

; with [Months] ([MonthStart])
as
(
	select @START_DATE [MonthStart]
	union all
	select dateadd(month, 1, [Months].[MonthStart]) [MonthStart]
	from [Months]
	where dateadd(month, 1, [Months].[MonthStart]) < @END_DATE
)

insert @TOTAL_MA_ELIGIBLE_MEMBERS_BY_MONTH ([PolicyNum], [MonthStart], [Members])
 select [PolicyNum], [Months].MonthStart, count(distinct MemberID) [Members]
from [PHP_EDW].[Master].MedicalEnrollAll enrl
join [Months] on [Months].MonthStart between enrl.EffDate and enrl.TermDate
where 1=1
	and [Type] = 'Medicare Advantage'
	--and EffDate <= @END_DATE
	--and isnull(TermDate, @FOREVER) >= @START_DATE  
	and TermDate > EffDate
	group by [PolicyNum], [Months].MonthStart
order by left([PolicyNum],5), substring([PolicyNum],6,3)
			, [Months].MonthStart

-- Update for each implemented data source ..

UPDATE_ELIGIBLE_MEMBERS:

if @UPDATE_ELIGIBLE_MEMBERS != 'Y' goto UPDATE_PMPM

--set @MSG = format(getdate(), 'HH:mm:ss') +  ': Update [The number of enrollees eligible] :' ; raiserror(@MSG, 0, 1 ) with nowait;

----------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'Alivi'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--																																			join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--	set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
--	update supp 
--		set [The number of enrollees eligible] = mbr.Members
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber]
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
--end 

--set @DATASOURCE = 'LifeStation'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	
--from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--	set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
--	update supp 
--		set [The number of enrollees eligible] = mbr.Members
--		  , [The number of enrollees who utilized benefit once] = mbr.Members
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber]
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
--end 

------------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'ASH'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	
--from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--join [CMSReporting].[SBSC_Code] cod 
--on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--	set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
--	update supp 
--		set [The number of enrollees eligible] = mbr.Members
--		, [The number of enrollees who utilized benefit once] = mbr.Members
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber]
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
--end 

------------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'Delta Dental'    ------ Currently picked up FCL Dental. Since dental codes are the same hence used the same name
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--					join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--	set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;														
--	update supp 
--		set [The number of enrollees eligible] = mbr.Members
--		, [The number of enrollees who utilized benefit once] = mbr.Members
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber] 
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE

--	-- TEMP
--	--select 'Test1' [Query], * 
--	--from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 where [PBP Category] like '16%'

--end 

------------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'GA Foods'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--			join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--	set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
--	update supp 
--		set [The number of enrollees eligible] = mbr.Members
--		, [The number of enrollees who utilized benefit once] = mbr.Members
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber]
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
--end  

------------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'HCS'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--	set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
--	update supp 
--		set [The number of enrollees eligible] = mbr.Members
--		    , [The number of enrollees who utilized benefit once] = mbr.Members
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber]
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
--end  

------------------------------------------------------------------------------------------------------------------------------------------------



--set @DATASOURCE = 'Incomm'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	
--from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--				join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--	set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
--	update supp 
--		set [The number of enrollees eligible] = case when isnull([elig].[Members], 0) > mbr.Members then mbr.Members 
--		                                         else isnull([elig].[Members], 0) end
--			, [The number of enrollees who utilized benefit once] = case when isnull([elig].[Members], 0) > mbr.Members then mbr.Members 
--		                                         else isnull([elig].[Members], 0) end
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--				join [CMSReporting].[SBSC_Code] cod  on cod.SBSC_BaseCode = supp.[PBP Category] 
--	and cod.DataSource = @DATASOURCE
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber] 
--	cross apply ( select count(distinct med.[MemberID] ) [Members]
--					, pm.OTC, pm.FOOD, pm.DSNP
--					from  PHP_EDW.[Master].MedicalEnrollAll [med]
--					join [CMSReporting].[SBSC_Code] cod2 on cod2.SBSC_BaseCode = cod.SBSC_BaseCode
--					cross apply ( select top 1 [Wallet Name]
--												from [Medicare_Custom].[InComm].[EnrollmentDetailStaging] [enrl]	 
--												where enrl.[Member ID] = med.MemberID collate SQL_Latin1_General_CP1_CI_AS
--													and enrl.[Wallet Effective Date]	<= @END_DATE 
--													and [Wallet Expiry Date]					>= @START_DATE
--													--
--												order by case [Current Wallet Status] when 'Active' then 1 else 2 end, PHP_FileLoadDateTime desc
--											) [enrl]

--					join [Medicare_Custom].Incomm.PurseMapping pm  on pm.PolicyNum = med.PolicyNum collate SQL_Latin1_General_CP1_CI_AS
--						and pm.PurseTermDate >= @START_DATE
--						and pm.PurseEffDate  <= @END_DATE																														
--						and rtrim(pm.Incomm_PurseCode) = rtrim(enrl.[Wallet Name])
--						and 'Y' = case cod2.SBSC_Code when '13b' then pm.OTC
--						when '13c' then pm.FOOD
--						when '13g' then pm.DSNP
--											end
--					where [med].EffDate <= @END_DATE 
--						and [med].TermDate >= @START_DATE 
--						and med.[Type] = 'Medicare Advantage'
--						and med.PolicyNum = supp.PolicyNumber collate SQL_Latin1_General_Pref_CP1_CI_AS
--						-- and [med].PlanDesc like left(supp.PolicyNumber, 5)+'_'+substring(supp.PolicyNumber, 6, 1)+'%'

--				group by pm.OTC, pm.FOOD, pm.DSNP
									
--		) [elig]
--end  

------------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'NVA'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--update supp 
--		set [The number of enrollees eligible] = mbr.Members
--		    , [The number of enrollees who utilized benefit once] = mbr.Members
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber]
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
--end  

------------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'LifeStation'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--update supp 
--		set [The number of enrollees eligible] = mbr.Members
--		, [The number of enrollees who utilized benefit once] = mbr.Members
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber]
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
--end  

--set nocount off


--select sbsc.SBSC_BaseCode
--from [CMSReporting].[SBSC_Code] [sbsc]
--left join CMSReporting.QNXT_Benefits_2025 [qben] on qben.SBSC_Code = sbsc.SBSC_BaseCode
--where sbsc.DataSource = 'QNXT'
--  and qben.SBSC_Code is null
--group by sbsc.SBSC_BaseCode

--select * 
--from [CMSReporting].[SBSC_Code] [sbsc]
--where sbsc.DataSource != 'QNXT'
--and sbsc.SBSC_BaseCode != sbsc.SBSC_Code

--select * 
--from [CMSReporting].[SBSC_Code] [sbsc]
--where SupplementalBenefitDescription like '%meals%'


--join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE


----------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'QNXT'
--if 0 = (	select sum(isnull( [The number of enrollees eligible], 0))	
--from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--		join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE )
--begin
--	set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
--	update supp 
--		set [The number of enrollees eligible] = ISNULL([elig].[Members], 0)
--		    , [The number of enrollees who utilized benefit once] = ISNULL([elig].[Members], 0)
--	from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--	join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and DataSource in (@DATASOURCE) -- , 'Delta Dental', 'NVA', 'HCS')
--	cross apply (	select count(distinct enrl.[MemberID]) [Members] 						
--								from PHP_EDW.[Master].MedicalEnrollAll [enrl]
--								join CMSReporting.QNXT_Benefits_2025 [bene] 
--								on bene.orgpolicyid = enrl.orgpolicyid collate SQL_Latin1_General_CP1_CI_AS
--								--and bene.PlanId = enrl.PlanId collate SQL_Latin1_General_CP1_CI_AS 
--								--and bene.RateId = enrl.rateid collate SQL_Latin1_General_CP1_CI_AS 
--								and bene.SBSC_Code = cod.SBSC_Code
--								where 1=1
--							    and enrl.EffDate  <= @END_DATE
--							    and isnull(enrl.TermDate, @FOREVER) >= @START_DATE
--									and enrl.PolicyNum = supp.[PolicyNumber] collate SQL_Latin1_General_Pref_CP1_CI_AS

--						) [elig]
		

--	update supp 
--			set [The number of enrollees eligible] = mbr.Members
--			   , [The number of enrollees who utilized benefit once] = mbr.Members
--		from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--		join @TOTAL_MA_ELIGIBLE_MEMBERS mbr on mbr.[PolicyNum] = supp.[PolicyNumber]
--		join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] 
--		 and cod.DataSource = @DATASOURCE
--		where supp.[The number of enrollees eligible] = 0
--		  and supp.[PBP Category] = 'OON'

	
--	set nocount on 

--end  


-----------------------------------------------------------------------------------------------------
-- Update Transaction-based columns for monthly enrollment (PMPM)-based counts and dollar amounts ---

	-- Vendor				Utilization Units		Payment Arrangements
	-------------------------------------------------------------------
	-- Alivi				PMPM+Usage					PMPM for admin costs, plus FFS
	-- ASH					Capitated						PMPM
	-- Delta Dental	Capitated						PMPM
	-- HCS					Capitated						PMPM
	-- Incomm				PMPM+Usage					PMPM for admin costs, plus FFS
	-- NVA					PMPM+Usage					PMPM for admin costs, plus FFS

-- Columns:
	---------------------------------------------------------------------------------------------
	-- NO! [The number of enrollees who utilized benefit once]
	-- NO! [The total instances of utilization among eligible enrollees]
	-- NO! [The median number of utilizations among enrollees who utilized the benefit at least once]
	-- [The total net amount incurred by plan to offer the benefit]
	-- NO! [The total out-of-pocket-cost per utilization for enrollees]
-----------------------------------------------------------------------------------------------------
UPDATE_PMPM:

if @UPDATE_PMPM != 'Y' goto UPDATE_USAGE_BASED

--declare @DATASOURCE varchar(20)
--set @DATASOURCE = 'ASH'
--declare @START_DATE date = '2024-01-01'
--declare @END_DATE	 date = '2024-12-31'
begin
	set @MSG = format(getdate(), 'HH:mm:ss') +  ': Update Transaction-based columns for monthly enrollment (PMPM)-based counts and dollar amounts ..' ; raiserror(@MSG, 0, 1 ) with nowait;

	update supp 
		set [The total net amount incurred by plan to offer the benefit] = case when supp.[The number of enrollees eligible] = 0  then 0  else isnull(cap.[CapitationAmount], 0) end
  from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
	join (  select supp.PolicyNumber, supp.[PBP Category], isnull(pmpm.Amount, 0) [CapitationAmount]
					--select cod.DataSource, supp.PolicyNumber, [vendor].Categories, enrl.MemberMonths [MemberMonths], pmpm.CapitationRate, pmpm.Amount [Per-Category Cap Amount]
					from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
					join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category]
					cross apply ( select count(distinct SBSC_BaseCode) [Categories] from [CMSReporting].[SBSC_Code] where DataSource = cod.DataSource ) [vendor]
					cross apply ( select count(distinct enrl.MemberId+format(mth.MonthStart, 'yyyyMMdd')) [MemberMonths], enrl.PolicyNum 
						from PHP_EDW.Master.MedicalEnrollAll [enrl]
						join @Months [mth] on mth.MonthStart <= enrl.TermDate
						and mth.MonthStart >= enrl.EffDate
						where enrl.[Type] = 'Medicare Advantage'
							and enrl.PolicyNum = supp.PolicyNumber collate SQL_Latin1_General_Pref_CP1_CI_AS
							and enrl.[EffDate] <= @END_DATE
							and enrl.[TermDate] >= @START_DATE

						group by enrl.PolicyNum
					) [enrl]

					cross apply ( select ((enrl.MemberMonths*rate.CapitationRate)/[vendor].Categories) [Amount]
													, rate.CapitationRate
									from [Medicare_Custom].[CMSReporting].[SupplementalVendorRates] [rate] 
									where [Rate].PlanYear = year(@START_DATE)
										and [Rate].[VendorName] = cod.DataSource
										and [Rate].[Contract] = left(enrl.PolicyNum, 5) collate SQL_Latin1_General_CP1_CI_AS
										and [Rate].[PBP] = substring(enrl.PolicyNum, 6, 3) collate SQL_Latin1_General_CP1_CI_AS				
									) [pmpm]		 
				group by supp.PolicyNumber, supp.[PBP Category], isnull(pmpm.Amount, 0)
			) [cap] on cap.PolicyNumber = supp.PolicyNumber
							and cap.[PBP Category] = supp.[PBP Category]

end

-----------------------------------------------------------------------------------------------------
-- Update Transaction-based columns for usage-based counts and dollar amounts ---

	-- Vendor				Utilization Units		Payment Arrangements
	-------------------------------------------------------------------
	-- Alivi				PMPM+Usage					PMPM for admin costs, plus FFS
	-- ASH					Capitated						PMPM
	-- Delta Dental	Capitated						PMPM														
	-- HCS					Capitated						PMPM
	-- Incomm				PMPM+Usage					PMPM for admin costs, plus FFS
	-- NVA					PMPM+Usage					PMPM for admin costs, plus FFS
	-- LifeStation  Per 

-- Columns:
	---------------------------------------------------------------------------------------------
	-- [The number of enrollees who utilized benefit once]						(Applies to all of the above vendors)
	-- [The total instances of utilization among eligible enrollees]			(Applies to all of the above vendors)
	-- [The median number of utilizations among enrollees who utilized the benefit at least once]		(Applies to all of the above vendors)
	-- [The total net amount incurred by plan to offer the benefit]				(Applies only to vendor contracts with a FFS billing component)
	-- [The total out-of-pocket-cost per utilization for enrollees]				(Applies to all of the above vendors)
-----------------------------------------------------------------------------------------------------

UPDATE_USAGE_BASED:


if @UPDATE_USAGE_BASED != 'Y' goto FINAL_QUERY

set @MSG = format(getdate(), 'HH:mm:ss') +  ': Update Transaction-based columns for usage-based counts and dollar amounts :' ; raiserror(@MSG, 0, 1 ) with nowait;

----------------------------------------------------------------------------------------------------------------------------------------------
--set @DATASOURCE = 'Alivi'
--set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;

--update supp 
--	set		[The number of enrollees who utilized benefit once]					= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.UniqueMembers end
--			, [The total instances of utilization among eligible enrollees]		= case when supp.[The number of enrollees eligible] = 0  then 0  
--			                                                                      when trans.BilledTransactions <= 0 then 0 else trans.BilledTransactions end
--			, [The median number of utilizations among enrollees who utilized the benefit at least once]	= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.MeanTransactionsPerMemberUsing end
--			, [The total net amount incurred by plan to offer the benefit]		= case when supp.[The number of enrollees eligible] = 0  then 0 
--			                                                     when (trans.PlanPaid + [The total net amount incurred by plan to offer the benefit]) < 0 then 0
--			                                                              else (trans.PlanPaid + [The total net amount incurred by plan to offer the benefit]) end -- include the already-loaded PMPM amount, if any.
--			, [The total out-of-pocket-cost per utilization for enrollees]		= case when supp.[The number of enrollees eligible] = 0  then 0 
--			                                                                      when (trans.MemberPaid/trans.BilledTransactions) < 0 then 0
--			                                                                      else trans.MemberPaid/trans.BilledTransactions end

--from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
--join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
--cross apply ( select	fees.PolicyNum
--										, count(distinct fees.SubscriberNumber) [UniqueMembers]
--										,	count(distinct fees.ProviderReferenceID) [BilledTransactions]
--										,	ceiling(count(distinct fees.ProviderReferenceID)/count(distinct SubscriberNumber)) [MeanTransactionsPerMemberUsing]
--										, sum(isnull(fees.AdminFee, 0.0)) [PlanPaid]
--										, 0.0 [MemberPaid]

--							from [Alivi].[AdminFees] [fees]
--							where fees.PolicyNum = supp.PolicyNumber
--								and fees.AdminFee != 0.0
--								and isnull(fees.AppointmentTime, fees.ScheduledTime) between @START_DATE and @END_DATE
--							group by fees.PolicyNum
--						) [trans]

--;with NumberedValues as
--(	select	value
--				, row_number() over (order by value) [row_num],
--				, count(*) over () [total_count]
--    from numbers
--)
--select avg(value) AS median
--from NumberedValues
--where row_num in ( (total_count + 1) / 2, (total_count + 2) / 2 );

	

----------------------------------------------------------------------------------------------------------------------------------------------
set @DATASOURCE = 'LifeStation'
set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;

update supp 
	set		[The number of enrollees who utilized benefit once]			=	case when supp.[The number of enrollees eligible] = 0  then 0  
														   else trans.UniqueMembers end
			,  [The total instances of utilization among eligible enrollees]	= case when supp.[The number of enrollees eligible] = 0  then 0 
			                                               else trans.BilledTransactions end
			, [The median number of utilizations among enrollees who utilized the benefit at least once] = case when supp.[The number of enrollees eligible] = 0  
			                                                then 0  else trans.MeanTransactionsPerMemberUsing end
			, [The total net amount incurred by plan to offer the benefit]	= case when supp.[The number of enrollees eligible] = 0  then 0 
                                     else trans.PlanPaid + [The total net amount incurred by plan to offer the benefit] end -- include the already-loaded PMPM amount, if any.
			, [The total out-of-pocket-cost per utilization for enrollees]	= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.MemberPaid/trans.BilledTransactions end
			, [The median out-of-pocket cost for enrollees] = case when supp.[The number of enrollees eligible] = 0 then 0 else trans.MedianOOP end

from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
cross apply (
    -- Outer aggregation: totals + median OOP
    select
        m.PolicyNum,
        count(distinct m.MemberID) as UniqueMembers,
        sum(m.BilledMonths) as BilledTransactions,
        ceiling(sum(m.BilledMonths) * 1.0 / count(distinct m.MemberID)) as MeanTransactionsPerMemberUsing,
        sum(m.BilledMonths) * m.TransactionRate as PlanPaid,
        0.0 as MemberPaid,

        -- ⭐ Median OOP per enrollee
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.MemberOOP)
            OVER (PARTITION BY m.PolicyNum) as MedianOOP

    from (
        -- Inner aggregation: per‑member OOP totals
        select
            enrl.PolicyNum,
            trans.MemberID,
            datediff(month, trans.RequestDate, @END_DATE) + 1 as BilledMonths,
            rate.TransactionRate,
            0.0 as MemberOOP   -- LifeStation has no member OOP, but median requires this field
        from LifeStation.MemberRequests trans
        join PHP_EDW.Master.MedicalEnrollAll enrl
            on enrl.MemberId = trans.MemberID collate SQL_Latin1_General_Pref_CP1_CI_AS
           and enrl.EffDate <= trans.RequestDate
           and enrl.TermDate >= trans.RequestDate
           and enrl.PolicyNum = supp.PolicyNumber collate SQL_Latin1_General_Pref_CP1_CI_AS
        join CMSReporting.SupplementalVendorRates rate
            on rate.VendorName = @DATASOURCE
           and rate.Contract = left(supp.PolicyNumber, 5)
           and rate.PBP = substring(supp.PolicyNumber, 6, 3)
        where trans.RequestDate between @START_DATE and @END_DATE
    ) m
    group by m.PolicyNum, m.TransactionRate, m.MemberOOP
) trans


----------------------------------------------------------------------------------------------------------------------------------------------
set @DATASOURCE = 'ASH'

set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;

update supp 
	set		[The number of enrollees who utilized benefit once]				=	case when supp.[The number of enrollees eligible] = 0  then 0  else trans.UniqueMembers end
			, [The total instances of utilization among eligible enrollees]		= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.BilledTransactions end
			, [The median number of utilizations among enrollees who utilized the benefit at least once]	= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.MeanTransactionsPerMemberUsing end
			, [The total net amount incurred by plan to offer the benefit]	= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.PlanPaid + [The total net amount incurred by plan to offer the benefit] end -- include the already-loaded PMPM amount, if any.
			, [The total out-of-pocket-cost per utilization for enrollees]	= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.MemberPaid/trans.BilledTransactions end
			, [The median out-of-pocket cost for enrollees] = case when supp.[The number of enrollees eligible] = 0 then 0 else trans.MedianOOP end

from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
cross apply (
    -- Outer aggregation: totals + median OOP
    select
        m.PolicyNum,
        m.SBSC_BaseCode,
        count(distinct m.MemberID) as UniqueMembers,
        sum(m.Visits) as BilledTransactions,
        sum(m.Visits) * 1.0 / count(distinct m.MemberID) as MeanTransactionsPerMemberUsing,
        sum(m.PlanPaid) as PlanPaid,
        sum(m.MemberPaid) as MemberPaid,

        -- ⭐ Median OOP per enrollee
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.MemberOOP)
            OVER (PARTITION BY m.PolicyNum, m.SBSC_BaseCode) as MedianOOP

    from (
        -- Inner aggregation: per‑member OOP totals
        select
            enrl.PolicyNum,
            cod2.SBSC_BaseCode,
            trans.MemberID,
            sum(trans.Visits) as Visits,
            0 as PlanPaid,
            0 as MemberPaid,
            0 as MemberOOP   -- ASH has no OOP, but structure supports median
        from PHP_EDW.Master.MedicalEnrollAll enrl
        join CMSReporting.SBSC_Code cod2
            on cod2.SBSC_BaseCode = cod.SBSC_BaseCode
        join ASH.AllMemberTransactions trans
            on trans.MemberID = enrl.MemberId collate SQL_Latin1_General_CP1_CI_AS
           and trans.DOS_Year = @REPORTING_YEAR
           and trans.TransactionType = cod2.SupplementalBenefitDescription
        where enrl.EffDate <= @END_DATE
          and enrl.TermDate >= @START_DATE
          and enrl.Type = 'Medicare Advantage'
          and enrl.PolicyNum = supp.PolicyNumber collate SQL_Latin1_General_Pref_CP1_CI_AS
        group by enrl.PolicyNum, cod2.SBSC_BaseCode, trans.MemberID
    ) m
    group by m.PolicyNum, m.SBSC_BaseCode, m.MemberOOP
) trans


----------------------------------------------------------------------------------------------------------------------------------------------

set @DATASOURCE = 'Delta Dental'

set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;	
-- Delta Dental total net amount incurred ..
update supp 
	set		[The number of enrollees who utilized benefit once]			=	case when supp.[The number of enrollees eligible] = 0  then 0  else clm.UniqueMembers end
			,  [The total instances of utilization among eligible enrollees]			= case when supp.[The number of enrollees eligible] = 0  then 0  else clm.BilledTransactions end
			, [The median number of utilizations among enrollees who utilized the benefit at least once]	= case when supp.[The number of enrollees eligible] = 0  then 0  else clm.MeanTransactionsPerMemberUsing end
			, [The total net amount incurred by plan to offer the benefit]		= case when supp.[The number of enrollees eligible] = 0  then 0 
			             --when clm.MeanTransactionsPerMemberUsing > (clm.PlanPaid + [The total net amount incurred by plan to offer the benefit]) then clm.MeanTransactionsPerMemberUsing
			                                                    else clm.PlanPaid + [The total net amount incurred by plan to offer the benefit] end -- include the already-loaded PMPM amount, if any.
			, [The total out-of-pocket-cost per utilization for enrollees]		= case when supp.[The number of enrollees eligible] = 0  then 0  else clm.MemberPaid/clm.BilledTransactions end
			, [The median out-of-pocket cost for enrollees] = case when supp.[The number of enrollees eligible] = 0 then 0 else clm.MedianOOP end

from (
    -- Outer aggregation: totals + median OOP
    select
        m.PolicyNum,
        m.SBSC_Code,
        count(distinct m.MemberID) as UniqueMembers,
        count(distinct m.ClaimNumber collate SQL_Latin1_General_CP1_CI_AS + m.SBSC_Code) as BilledTransactions,
        ceiling(
            count(distinct m.ClaimNumber collate SQL_Latin1_General_CP1_CI_AS + m.SBSC_Code)
            / count(distinct m.MemberID)
        ) as MeanTransactionsPerMemberUsing,
        sum(m.PlanPaid) as PlanPaid,
        sum(m.MemberPaid) as MemberPaid,

        -- ⭐ Median OOP per enrollee
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.MemberOOP)
            OVER (PARTITION BY m.PolicyNum, m.SBSC_Code) as MedianOOP

    from (
        -- Inner aggregation: per‑member OOP totals
        select
            enrl.PolicyNum,
            cod.SBSC_Code,
            clm.[MemberNumber] as MemberID,
            clm.[CLAIMNUMBER] as ClaimNumber,

            sum(
                case when isnumeric(clm.[PaidAmt]) = 1
                     then convert(money, clm.[PaidAmt])
                     else 0 end
            ) as MemberOOP,

            sum(
                case when isnumeric(clm.[PaidAmt]) = 1
                     then convert(money, clm.[PaidAmt])
                     else 0 end
            ) as PlanPaid,

            sum(
                case when isnumeric(clm.[PaidAmt]) = 1
                     then convert(money, (clm.AmtToPayMember + clm.AmtCopay + clm.Deductible))
                     else 0 end
            ) as MemberPaid

        from [CORP-PHPSQL01D].Backend.FCL.Claims clm  --SMHP_Custom.DeltaDental.Claims clm
        cross apply (
            select top 1 replace(left(PlanDesc,9), '_','') as PolicyNum
            from Plandata_Prod.dbo.MemberCmsHic mbi
            join PHP_EDW.Medicare.MemberEnrollDetails enrl
                on enrl.InternalMemberID = mbi.MemId
               and enrl.EnrollEffDate <= convert(date, clm.[Servicedatefrom])
               and isnull(enrl.EnrollTermDate, @FOREVER ) >= cast(clm.[Servicedatefrom] AS date)     -- convert(date, clm.[Servicedatefrom])  
            where enrl.Memberid = clm.[MemberNumber]                    --mbi.Hic COLLATE SQL_Latin1_General_Pref_CP1_CI_AS
              and mbi.EffDate <= convert(date, cast(clm.[Servicedateto] AS date) )
              and mbi.TermDate >= cast(clm.[Servicedatefrom] AS date)
        ) enrl
        join Medicare_Custom.CMSReporting.ProcedureCodeToSBSC_Code_External codext
            on codext.StartProcedureCode <= clm.[ProcedureCode] collate SQL_Latin1_General_CP1_CI_AS
           and codext.EndProcedureCode >= clm.[ProcedureCode] collate SQL_Latin1_General_CP1_CI_AS
           and codext.Category = 'Dental'
           and codext.Source = 'Operations'
        join Medicare_Custom.CMSReporting.SBSC_Code cod
            on cod.SBSC_Code = codext.SBSC_Code
           and cod.DataSource = @DATASOURCE
        where cast(clm.[Servicedatefrom] AS date) between @START_DATE and @END_DATE
        group by enrl.PolicyNum, cod.SBSC_Code, clm.[MemberNumber], clm.[CLAIMNUMBER]
    ) m
    group by m.PolicyNum, m.SBSC_Code, m.MemberOOP
) clm
join [Medicare_Custom].[CMSReporting].[SupplementalBenefitUtilizationAndCosts_2025] supp on supp.[SBSC_Code] = clm.SBSC_Code
and supp.PolicyNumber = clm.PolicyNum collate SQL_Latin1_General_CP1_CI_AS
join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE



----------------------------------------------------------------------------------------------------------------------------------------------
set @DATASOURCE = 'GA Foods'


--select PolicyNumber, count(distinct MemberID) [Members], sum(TotalPaid) [Paid], sum(DeliveryTotalQuantity) [Meals], sum(TotalPaid)/sum(DeliveryTotalQuantity) [PerMeal]
--from [GAFoods].[Billing] 
--where year(DeliveryDate) = 2024
--group by PolicyNumber
--order by PolicyNumber

set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
update supp 
	set		[The number of enrollees who utilized benefit once]																					=	case when supp.[The number of enrollees eligible] = 0  then 0  else bil.UniqueMembers end
			, [The total instances of utilization among eligible enrollees]																= case when supp.[The number of enrollees eligible] = 0  then 0  else bil.BilledTransactions end
			, [The median number of utilizations among enrollees who utilized the benefit at least once]	= case when supp.[The number of enrollees eligible] = 0  then 0  else bil.MeanTransactionsPerMemberUsing end
			, [The total net amount incurred by plan to offer the benefit]																= case when supp.[The number of enrollees eligible] = 0  then 0  else bil.PlanPaid + [The total net amount incurred by plan to offer the benefit] end -- include the already-loaded PMPM amount, if any.
			, [The total out-of-pocket-cost per utilization for enrollees]																= case when supp.[The number of enrollees eligible] = 0  then 0  else bil.MemberPaid/bil.BilledTransactions end
			, [The median out-of-pocket cost for enrollees] = case when supp.[The number of enrollees eligible] = 0 then 0 else bil.MedianOOP end

from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
cross apply (
    -- Outer aggregation: compute totals + median OOP
    select
        m.PolicyNum,
        m.SBSC_BaseCode,
        count(distinct m.MemberID) as UniqueMembers,
        sum(m.DeliveryTotalQuantity) as BilledTransactions,
        ceiling(sum(m.DeliveryTotalQuantity) / count(distinct m.MemberID)) as MeanTransactionsPerMemberUsing,
        sum(m.PlanPaid) as PlanPaid,
        sum(m.MemberPaid) as MemberPaid,

        -- ⭐ Median OOP per enrollee
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.MemberOOP)
            OVER (PARTITION BY m.PolicyNum, m.SBSC_BaseCode) as MedianOOP

    from (
        -- Inner aggregation: per-member OOP totals
        select
            enrl.PolicyNum,
            cod2.SBSC_BaseCode,
            bil.MemberID,
            sum(bil.DeliveryTotalQuantity) as DeliveryTotalQuantity,
            sum(
                case when isnumeric(bil.TotalPaid) = 1
                     then convert(money, bil.TotalPaid)
                     else 0 end
            ) as PlanPaid,
            0.0 as MemberPaid,  -- GAFoods has no member OOP
            0.0 as MemberOOP    -- but keep structure for median
        from PHP_EDW.Master.MedicalEnrollAll enrl
        join CMSReporting.SBSC_Code cod2
            on cod2.SBSC_BaseCode = cod.SBSC_BaseCode
        join GAFoods.Billing bil
            on bil.MemberID = enrl.MemberId collate SQL_Latin1_General_CP1_CI_AS
           and bil.DeliveryDate between @START_DATE and @END_DATE
           and bil.DeliveryDate >= enrl.EffDate
           and bil.DeliveryDate <= enrl.TermDate
        where enrl.EffDate <= @END_DATE
          and enrl.TermDate >= @START_DATE
          and enrl.Type = 'Medicare Advantage'
          and enrl.PolicyNum = supp.PolicyNumber collate SQL_Latin1_General_Pref_CP1_CI_AS
        group by enrl.PolicyNum, cod2.SBSC_BaseCode, bil.MemberID
    ) m
    group by m.PolicyNum, m.SBSC_BaseCode, m.MemberOOP
) bil


----------------------------------------------------------------------------------------------------------------------------------------------
HCS_CLAIMS:

set @DATASOURCE = 'HCS'
set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;

update supp 
	set		[The number of enrollees who utilized benefit once]			=	case when supp.[The number of enrollees eligible] = 0  then 0  else clm.UniqueMembers end
			, [The total instances of utilization among eligible enrollees]																= case when supp.[The number of enrollees eligible] = 0  then 0  else clm.BilledTransactions end
			, [The median number of utilizations among enrollees who utilized the benefit at least once]	= case when supp.[The number of enrollees eligible] = 0  then 0  else clm.MeanTransactionsPerMemberUsing end
			, [The total net amount incurred by plan to offer the benefit]																= case when supp.[The number of enrollees eligible] = 0  then 0  else clm.PlanPaid + [The total net amount incurred by plan to offer the benefit] end -- include the already-loaded PMPM amount, if any.
			, [The total out-of-pocket-cost per utilization for enrollees]																= case when supp.[The number of enrollees eligible] = 0  then 0  else clm.MemberPaid/clm.BilledTransactions end
			, [The median out-of-pocket cost for enrollees] = case when supp.[The number of enrollees eligible] = 0 then 0 else clm.MedianOOP end

from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
cross apply (
    -- per-member OOP
    select
        m.PolicyNum,
        m.SBSC_Code,
        count(distinct m.MemberID) as UniqueMembers,
        count(distinct convert(varchar(20), m.ClaimNumber) collate SQL_Latin1_General_CP1_CI_AS + m.SBSC_Code) as BilledTransactions,
        ceiling(
            count(distinct convert(varchar(20), m.ClaimNumber) collate SQL_Latin1_General_CP1_CI_AS + m.SBSC_Code)
            / count(distinct m.MemberID)
        ) as MeanTransactionsPerMemberUsing,
        sum(m.PlanPaid) as PlanPaid,
        sum(m.MemberPaid) as MemberPaid,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.MemberOOP)
            OVER (PARTITION BY m.PolicyNum, m.SBSC_Code) as MedianOOP
    from (
        select
            enrl.PolicyNum,
            cod2.SBSC_Code,
            clm.MemberID,
            clm.ClaimNumber,
            -- per-member OOP (sum across that member’s lines)
            sum(
                case when isnumeric(clm.MemberResponsibleAmt) = 1
                     then convert(money, clm.MemberResponsibleAmt)
                     else 0.0 end
            ) as MemberOOP,
            sum(
                case when isnumeric(clm.PaidAmt) = 1
                     then convert(money, clm.PaidAmt)
                     else 0.0 end
            ) as PlanPaid,
            sum(
                case when isnumeric(clm.MemberResponsibleAmt) = 1
                     then convert(money, clm.MemberResponsibleAmt)
                     else 0.0 end
            ) as MemberPaid
        from PHP_EDW.Master.MedicalEnrollAll enrl
        join CMSReporting.SBSC_Code cod2
            on cod2.SBSC_BaseCode = cod.SBSC_BaseCode
        join HCS.MedicareEncounters clm
            on clm.MemberID = enrl.MemberId collate SQL_Latin1_General_CP1_CI_AS
           and clm.ServiceFromDate between @START_DATE and @END_DATE
           and clm.ServiceFromDate >= enrl.EffDate
           and clm.ServiceFromDate <= enrl.TermDate
           and clm.ClaimLineStatus = 'Paid'
        join Medicare_Custom.CMSReporting.ProcedureCodeToSBSC_Code_External codext
            on codext.StartProcedureCode <= clm.ProcedureCode collate SQL_Latin1_General_CP1_CI_AS
           and codext.SBSC_Code = cod2.SBSC_BaseCode
        where enrl.EffDate <= @END_DATE
          and enrl.TermDate >= @START_DATE
          and enrl.[Type] = 'Medicare Advantage'
          and enrl.PolicyNum = supp.PolicyNumber collate SQL_Latin1_General_Pref_CP1_CI_AS
        group by enrl.PolicyNum, cod2.SBSC_Code, clm.MemberID, clm.ClaimNumber
    ) m
    group by m.PolicyNum, m.SBSC_Code, m.MemberOOP
) clm



----------------------------------------------------------------------------------------------------------------------------------------------	
set @DATASOURCE = 'Incomm'

set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;
-- Incomm enrollees who utilized benefit once, from Incomm transactions ..


drop table if exists #InComm_TransactionDetail
select trim([MemberNumber]) [MemberNumber], TransactionDateTime, trim(Wallet) [Wallet], WalletDisplayName, max(-TransactionAmount) [TransactionAmount], max(-AuthorizedAmount) [AuthorizedAmount]
			, convert(varchar(15), '') [PolicyNum], convert(char(1), '') [OTC], convert(char(1), '') [Food], convert(char(1), '') [DSNP]
into #InComm_TransactionDetail
from [SMHP_Custom].[InComm].[TransactionDetail] [trans]
where TransactionDateTime between @START_DATE and @END_DATE
and ResponseDescription = 'SUCCESS'			
and TransactionType	in ('Card Redemption', 'Card Redemption Reversal')
and exists ( select 1 
						 from [Medicare_Custom].[InComm].[EnrollmentDetailStaging] [enrl]	 
						 where enrl.[Member ID] = trans.MemberNumber collate SQL_Latin1_General_CP1_CI_AS
																and enrl.[Wallet Effective Date]	<= @END_DATE 
																and [Wallet Expiry Date]					>= @START_DATE
																and [Current Wallet Status]				= 'Active'										
					  ) 
group by MemberNumber, TransactionDateTime, Wallet, WalletDisplayName

alter table #InComm_TransactionDetail add [Difference] as ([TransactionAmount]-[AuthorizedAmount]) persisted
alter table #InComm_TransactionDetail alter column MemberNumber varchar(12) not null
alter table #InComm_TransactionDetail alter column TransactionDateTime datetime not null
alter table #InComm_TransactionDetail alter column Wallet varchar(50) not null
alter table #InComm_TransactionDetail alter column [PolicyNum] varchar(15) not null
alter table #InComm_TransactionDetail alter column [OTC] char(1) not null
alter table #InComm_TransactionDetail alter column [Food] char(1) not null
alter table #InComm_TransactionDetail alter column [DSNP] char(1) not null
alter table #InComm_TransactionDetail add primary key clustered (MemberNumber, TransactionDateTime, [PolicyNum], [OTC], [Food], [DSNP], Wallet)
--create index ix_tmp_InComm_TransactionDetail on #InComm_TransactionDetail (MemberNumber, TransactionDateTime, Wallet ) include (TransactionAmount, AuthorizedAmount, [Difference])

set @MSG = format(getdate(), 'HH:mm:ss') +  ':     #InComm_TransactionDetail loaded.' + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;

update trans	
	set [PolicyNum] = pm.PolicyNum
	, [OTC]  = case when WalletDisplayName like '%OTC%' or pm.OTC = 'Y' then 'Y' else 'N' end
	, [Food] = case when WalletDisplayName like '%Food%' or pm.Food = 'Y' then 'Y' else 'N' end
	, [DSNP] = case when WalletDisplayName like '%DSNP%' or pm.DSNP = 'Y' then 'Y' else 'N' end
from #InComm_TransactionDetail trans
join [Medicare_Custom].Incomm.PurseMapping pm  on pm.Incomm_PurseCode = trans.Wallet
	and pm.PurseTermDate >= trans.TransactionDateTime
	and pm.PurseEffDate  <= trans.TransactionDateTime
join [PHP_EDW].Master.MedicalEnrollAll [enrl] on enrl.MemberId = trans.MemberNumber collate SQL_Latin1_General_Pref_CP1_CI_AS
	and enrl.EffDate <= trans.TransactionDateTime
	and enrl.TermDate >= trans.TransactionDateTime
	and enrl.PolicyNum = pm.PolicyNum collate SQL_Latin1_General_Pref_CP1_CI_AS
																							

set @MSG = format(getdate(), 'HH:mm:ss') +  ':     #InComm_TransactionDetail updated.' + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;



update supp 
	set		[The number of enrollees who utilized benefit once]			=	case when supp.[The number of enrollees eligible] = 0  then 0  else trans.UniqueMembers end
			, [The total instances of utilization among eligible enrollees]		= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.BilledTransactions end
			, [The median number of utilizations among enrollees who utilized the benefit at least once]	= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.MeanTransactionsPerMemberUsing end
			, [The total net amount incurred by plan to offer the benefit]		= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.PlanPaid + [The total net amount incurred by plan to offer the benefit] end -- include the already-loaded PMPM amount, if any.
			, [The total out-of-pocket-cost per utilization for enrollees]		= case when supp.[The number of enrollees eligible] = 0  then 0  else trans.MemberPaid/trans.BilledTransactions end
			, [The median out-of-pocket cost for enrollees] = CASE WHEN supp.[The number of enrollees eligible] = 0 THEN 0 ELSE trans.MedianMemberPaidPerUtilization END

from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and cod.DataSource = @DATASOURCE
cross apply (   select enrl.PolicyNum
				, cod2.SBSC_Code
				, count(distinct case when trans.AuthorizedAmount > 0.0 then trans.[MemberNumber] else '' end) [UniqueMembers]
				, count(distinct format(trans.[TransactionDateTime], 'yyyyMMddHHmm')+trans.Wallet collate SQL_Latin1_General_Pref_CP1_CI_AS/*+cod2.SBSC_Code*/) [BilledTransactions]
				,	ceiling(count(distinct format(trans.[TransactionDateTime], 'yyyyMMddHHmm')+trans.Wallet collate SQL_Latin1_General_Pref_CP1_CI_AS/*+cod2.SBSC_Code*/) / count(distinct case when trans.AuthorizedAmount > 0.0 then trans.[MemberNumber] else '' end)) [MeanTransactionsPerMemberUsing]
				, sum( trans.AuthorizedAmount ) [PlanPaid]
				, sum( trans.[Difference] ) [MemberPaid]
				, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY trans.[Difference]) OVER (PARTITION BY enrl.PolicyNum, cod2.SBSC_Code) AS MedianMemberPaidPerUtilization
				--, -sum( case when isnumeric(trans.[Difference]) = 1 then convert(money, trans.[Difference]) else 0.0 end ) [MemberPaid]

				from  [PHP_EDW].Master.MedicalEnrollAll [enrl]
				join [CMSReporting].[SBSC_Code] cod2 on cod2.SBSC_BaseCode = cod.SBSC_BaseCode
				join #InComm_TransactionDetail [trans]	 on trans.MemberNumber = enrl.MemberId collate SQL_Latin1_General_CP1_CI_AS
				--and trans.TransactionDateTime between @START_DATE and @END_DATE
				and trans.TransactionDateTime >= enrl.EffDate
				and trans.TransactionDateTime <= enrl.TermDate
				--and trans.ResponseDescription = 'SUCCESS'			
				--and trans.TransactionType			= 'Card Redemption'
				and trans.PolicyNum = enrl.PolicyNum collate SQL_Latin1_General_CP1_CI_AS
				and 'Y' = case cod2.SBSC_BaseCode when '13b' then trans.OTC
				when '13c' then trans.FOOD
				when '13g' then trans.DSNP
				end
				and  trans.WalletDisplayName like case when cod2.SBSC_BaseCode = '13b'  then '%OTC%'
					when cod2.SBSC_BaseCode = '13c'  then '%Food%'
					when cod2.SBSC_BaseCode = '13g'  then '%DSNP%'
														end
				where enrl.EffDate <=  @END_DATE
					and enrl.TermDate >= @START_DATE
					and enrl.[Type] = 'Medicare Advantage'		
					and enrl.PolicyNum = supp.PolicyNumber collate SQL_Latin1_General_Pref_CP1_CI_AS
	
				group by  enrl.PolicyNum
								, cod2.SBSC_Code, trans.[Difference]
		) [trans]

drop table if exists #InComm_TransactionDetail

--update supp
--	set [The number of enrollees eligible] =  [The number of enrollees who utilized benefit once]
--		, [The median number of utilizations among enrollees who utilized the benefit at least once] = [The total instances of utilization among eligible enrollees]	/ [The number of enrollees who utilized benefit once]
--from [Medicare_Custom].[CMSReporting].[SupplementalBenefitUtilizationAndCosts_2025] supp 	
--where supp.[PBP Category] in ('13b', '13c', '13g')
--  and [The number of enrollees eligible] < [The number of enrollees who utilized benefit once] 

----------------------------------------------------------------------------------------------------------------------------------------------	
set @DATASOURCE = 'NVA'

update supp 
set  [The number of enrollees who utilized benefit once] =
          case when supp.[The number of enrollees eligible] = 0 then 0 else clm.UniqueMembers end
     , [The total instances of utilization among eligible enrollees] =
          case when supp.[The number of enrollees eligible] = 0 then 0 else clm.BilledTransactions end
    , [The median number of utilizations among enrollees who utilized the benefit at least once] =
          case when supp.[The number of enrollees eligible] = 0 then 0 else clm.MeanTransactionsPerMemberUsing end
    , [The total net amount incurred by plan to offer the benefit] =
          case when supp.[The number of enrollees eligible] = 0 then 0
		  --when clm.MeanTransactionsPerMemberUsing > (clm.PlanPaid + [The total net amount incurred by plan to offer the benefit] )
		  --then clm.MeanTransactionsPerMemberUsing
               else clm.PlanPaid + [The total net amount incurred by plan to offer the benefit] end
    , [The total out-of-pocket-cost per utilization for enrollees] =
          case when supp.[The number of enrollees eligible] = 0 then 0
               else clm.MemberPaid / clm.BilledTransactions end
    , [The median out-of-pocket cost for enrollees] =
          case when supp.[The number of enrollees eligible] = 0 then 0 else clm.MedianOOP end

from (
    -- OUTER QUERY: aggregates + median
    select
        m.PolicyNum,
        m.SBSC_Code,
        count(distinct m.MemberID) as UniqueMembers,
        count(distinct m.ClaimNo collate SQL_Latin1_General_CP1_CI_AS + m.SBSC_Code) as BilledTransactions,
        ceiling(
            count(distinct m.ClaimNo collate SQL_Latin1_General_CP1_CI_AS + m.SBSC_Code)
            / count(distinct m.MemberID)
        ) as MeanTransactionsPerMemberUsing,
        sum(m.PlanPaid) as PlanPaid,
        sum(m.MemberOOP) as MemberPaid,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.MemberOOP)
            OVER (PARTITION BY m.PolicyNum, m.SBSC_Code) as MedianOOP
    from (
        -- INNER QUERY: per-member OOP
        select
            pol.PolicyNum,
            cod.SBSC_Code,
            clm.MemberID,
            clm.ClaimNo,
            case when isnumeric(clm.PaidAmt) = 1
                 then convert(money, clm.PaidAmt)
                 else 0.0 end as PlanPaid,
            case when isnumeric(clm.AllowedAmt) = 1 and isnumeric(clm.PaidAmt) = 1
                 then convert(money, clm.AllowedAmt) - convert(money, clm.PaidAmt)
                 else 0.0 end as MemberOOP
        from Medicare_Custom.NVA.Claims clm
        cross apply (
            select top 1 replace(left(PlanDesc,9), '_','') as PolicyNum
            from PHP_EDW.Medicare.MemberEnrollDetails
            where MemberID = clm.MemberID collate SQL_Latin1_General_Pref_CP1_CI_AS
              and EnrollEffDate <= convert(date, clm.DOS)
              and EnrollTermDate >= convert(date, clm.DOS)
        ) pol
        join Medicare_Custom.CMSReporting.ProcedureCodeToSBSC_Code_External codext
            on codext.StartProcedureCode <= clm.ProcedureCode collate SQL_Latin1_General_CP1_CI_AS
           and codext.EndProcedureCode   >= clm.ProcedureCode collate SQL_Latin1_General_CP1_CI_AS
           and codext.Category = 'Vision'
           and codext.Source   = 'Operations'
        join Medicare_Custom.CMSReporting.SBSC_Code cod
            on cod.SBSC_Code = codext.SBSC_Code
           and cod.DataSource = @DATASOURCE
        where clm.DOS between @START_DATE and @END_DATE
    ) m
    group by m.PolicyNum, m.SBSC_Code, m.MemberOOP
) clm
join Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
  on supp.SBSC_Code   = clm.SBSC_Code
 and supp.PolicyNumber = clm.PolicyNum collate SQL_Latin1_General_CP1_CI_AS;

----------------------------------------------------------------------------------------------------------------------------------------------	
QNXT_CLAIMS:

set @DATASOURCE = 'QNXT'

set @MSG = format(getdate(), 'HH:mm:ss') +  ':     Updating ' +  @DATASOURCE + ' ..' ; raiserror(@MSG, 0, 1 ) with nowait;

--select *  --[The total net amount incurred by plan to offer the benefit]
--from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--where Contract = 'H7680'
--  and PBP = '009'
--	and [PBP Category] = '13A' 
--goto FINAL_QUERY

update supp 
	set		[The number of enrollees who utilized benefit once]		=	case when supp.[The number of enrollees eligible] = 0  then 0  else round(clm.UniqueMembers, 0) end
			, [The total instances of utilization among eligible enrollees]		= case when supp.[The number of enrollees eligible] = 0  then 0  else round(clm.BilledTransactions, 0) end
			, [The median number of utilizations among enrollees who utilized the benefit at least once]	= case when supp.[The number of enrollees eligible] = 0  then 0  else round(clm.MeanTransactionsPerMemberUsing, 0) end
			, [The total net amount incurred by plan to offer the benefit]			= case when supp.[The number of enrollees eligible] = 0  then 0  else round(clm.PlanPaid + [The total net amount incurred by plan to offer the benefit], 2) end -- include the already-loaded PMPM amount, if any.
			, [The total out-of-pocket-cost per utilization for enrollees]			= case when supp.[The number of enrollees eligible] = 0  then 0  else round(clm.MemberPaid/clm.BilledTransactions, 2) end
			, [The median out-of-pocket cost for enrollees] = CASE WHEN supp.[The number of enrollees eligible] = 0 THEN 0 ELSE clm.MedianOOP END

from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
join [CMSReporting].[SBSC_Code] cod on cod.SBSC_BaseCode = supp.[PBP Category] and DataSource in (@DATASOURCE)
cross apply ( select case when supp.[PBP Category] in ('4c1') then 0.6
													when supp.[PBP Category] in ('4c2') then 0.4
													else 1.0 
							end [factor] ) [split]
cross apply (	select enrl.[PolicyNum]
							, isnull(bene2.SBSC_Code, bene_oon.SBSC_Code) [SBSC_Code]
							--, isnull(bene.SBSC_Code, bene2.SBSC_Code) [SBSC_Code]
							, [split].[factor]*count(distinct clm.[memid]) [UniqueMembers]
							, [split].[factor]*count(distinct clm.[ClaimId] collate SQL_Latin1_General_CP1_CI_AS+cod2.SBSC_Code) [BilledTransactions]
							,	ceiling([split].[factor]*count(distinct clm.[ClaimId] collate SQL_Latin1_General_CP1_CI_AS+cod2.SBSC_Code) / count(distinct clm.[memid])) [MeanTransactionsPerMemberUsing]
							, [split].[factor]*sum( clmdtl.[AmountPaid]) [PlanPaid]
							, [split].[factor]*sum( clmdtl.[MemAmt] ) [MemberPaid] 
							, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY clmdtl.MemAmt) 
							OVER (PARTITION BY enrl.PolicyNum, isnull(bene2.SBSC_Code, bene_oon.SBSC_Code)) * [split].[factor] AS MedianOOP
							--from PHP_EDW.Master.AllClaims [clm]
							from plandata_prod.dbo.claim [clm]
							join PHP_EDW.[dbo].[vwLineOfBusinessByPlan] lob on lob.planid = clm.planid
							and lob.LOB = 'Medicare Advantage'
							join plandata_prod.dbo.claimdetail [clmdtl] on clmdtl.claimid = clm.claimid
							and clmdtl.status in ('OKAY','WARN','PEND')
							join plandata_prod.dbo.benefit [ben] on ben.benefitid = clmdtl.benefitid
							join [CMSReporting].[SBSC_Code] cod2 on cod2.SBSC_BaseCode = cod.SBSC_BaseCode
							join plandata_prod.dbo.enrollkeys [ek] on ek.enrollid = clm.enrollid
							join PHP_EDW.[Master].MedicalEnrollAll [enrl] on enrl.MemberID = ek.carriermemid collate SQL_Latin1_General_Pref_CP1_CI_AS
							and enrl.enrollid =  clm.enrollid
							--and enrl.EffDate  <= clm.StartServiceDate
							--and enrl.TermDate >= clm.StartServiceDate
							and enrl.PolicyNum = supp.[PolicyNumber] collate SQL_Latin1_General_Pref_CP1_CI_AS
							left join CMSReporting.QNXT_Benefits_2025 [bene2] on 1=1
							and bene2.orgpolicyid = enrl.orgpolicyid collate SQL_Latin1_General_CP1_CI_AS
							and bene2.RateId = enrl.rateid collate SQL_Latin1_General_CP1_CI_AS
							and bene2.[BenefitID] = clmdtl.[BenefitID] collate SQL_Latin1_General_CP1_CI_AS
							and bene2.SBSC_Code = cod2.SBSC_Code collate SQL_Latin1_General_CP1_CI_AS

							outer apply ( select top 1 cod3.SBSC_Code
														from  [CMSReporting].[SBSC_Code] cod3
														where cod3.SBSC_Code = 'OON'
														  and right(rtrim(ben.[description]), 3) = 'OON'
															and cod3.SBSC_Code = cod2.SBSC_Code collate SQL_Latin1_General_CP1_CI_AS
															and cod3.SBSC_Code != bene2.SBSC_Code
										) [bene_oon]
							

						where 1=1 -- clm.LOB = 'Medicare Advantage'
						and clm.status in ('PAID','PAY','ADJUDICATED','OPEN','WAITPAY','WAITPRICE')
						and clm.startdate between @START_DATE and @END_DATE
							-- and clm.StartServiceDate  between @START_DATE and @END_DATE
							--and clm.ClaimStatus = 'PAID'
							--and clm.Package = supp.[PolicyNumber] collate SQL_Latin1_General_Pref_CP1_CI_AS
						and isnull(bene2.SBSC_Code, bene_oon.SBSC_Code) is not null
							-- and isnull(bene.SBSC_Code, bene2.SBSC_Code) is not null
						group by enrl.[PolicyNum]
							, isnull(bene2.SBSC_Code, bene_oon.SBSC_Code), clmdtl.MemAmt
						--, isnull(bene.SBSC_Code, bene2.SBSC_Code)
							
					) [clm]


-----------------------------------------------------------------------------------------------------
-- FINAL_QUERY --------------------------------------------------------------------------------------

FINAL_QUERY:
update supp
	set		[Network Type] = 'INN'
from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 [supp]

update supp
	set		[How the plan accounts for the cost of the benefit] = 'Plan paid amount from claims'
			, [The type of payment arrangement(s) the plan used to implement the benefit] = 'Internal claims system'
from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 [supp]
join Medicare_Custom.CMSReporting.SBSC_Code sbsc on sbsc.SBSC_Code = supp.SBSC_Code
where rtrim(isnull([The type of payment arrangement(s) the plan used to implement the benefit], '')) = ''
									and sbsc.DataSource = 'QNXT'
									and supp.[Unit of utilization used by Plan] = 'Visits'


--UPDATE supp
--SET
--    [How is the SB offered?] = 'NO'
--FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
--WHERE CONCAT(Contract, PBP) IN ('H5945032', 'H7680012')
--AND [PBP Category] = '13b'

-------- For M members ---------
--declare @REPORTING_YEAR int = 2026
--declare @START_DATE	date = datefromparts(@REPORTING_YEAR,  1,  1)
--declare @END_DATE		date = datefromparts(@REPORTING_YEAR, 12, 31)
UPDATE supp
SET 
    [The number of enrollees who utilized benefit once] = 
        CASE 
            WHEN supp.[The number of enrollees eligible] = 0 THEN 0
            ELSE dt.claimcount
        END,
    [The total net amount incurred by plan to offer the benefit] = 
        CASE 
            WHEN supp.[The number of enrollees eligible] = 0 THEN 0
            ELSE dt.paidamt
        END
FROM (
    SELECT NewCode,
           OldCode,
           OfferType
    FROM CMSReporting.PrimaryMapping
    UNPIVOT
    (
        OfferType FOR PlanID IN (
            [H5945-001],[H5945-002],[H5945-013],[H5945-014],[H5945-016],
            [H5945-017],[H5945-018],[H5945-027],[H5945-032],[H5945-801],
            [H5945-802],[H5945-804],[H5945-805],
            [H7239-001],[H7239-002],[H7239-003],
            [H7680-001],[H7680-002],[H7680-007],[H7680-009],[H7680-011],
            [H7680-012],[H7680-014],[H7680-015],[H7680-016],[H7680-017],
            [H7680-018],[H7680-019],[H7680-801]
        )
    ) u
    WHERE OfferType = 'M'
) grp
LEFT JOIN (
    SELECT clm.GroupNumber, codext.SBSC_Code, SUM(CAST(clm.paidamt AS MONEY)) AS paidamt, COUNT(*) AS claimcount
    FROM [CORP-PHPSQL01D].Backend.FCL.Claims clm
    JOIN Medicare_Custom.CMSReporting.ProcedureCodeToSBSC_Code_External codext
        ON codext.StartProcedureCode <= clm.[ProcedureCode] COLLATE SQL_Latin1_General_CP1_CI_AS
       AND codext.EndProcedureCode >= clm.[ProcedureCode] COLLATE SQL_Latin1_General_CP1_CI_AS
       AND codext.Category = 'Dental'
       AND codext.Source = 'Operations'
    WHERE YEAR(clm.servicedatefrom) =  @REPORTING_YEAR
      AND clm.MemberNumber COLLATE SQL_Latin1_General_Pref_CP1_CI_AS NOT IN (
            SELECT DISTINCT tt.HealthPlanID
            FROM PHP_EDW.Master.MedicalEnroll_INTSeg tt
            INNER JOIN (
                SELECT DISTINCT enrollid, effdate, termdate
                FROM PlanData_Prod.dbo.EnrollCoverage
                WHERE coveragecodeid = 'DENTALBUYUP'
                  AND effdate <= @END_DATE
                  AND termdate >= @START_DATE
            ) zz ON tt.enrollid = zz.enrollid
      )
    GROUP BY clm.GroupNumber, codext.SBSC_Code
) dt
ON grp.OldCode = dt.SBSC_Code
JOIN [CMSReporting].[SupplementalBenefitUtilizationAndCosts_2025] supp
ON dt.GroupNumber = CONCAT(supp.Contract, '-', supp.PBP)
AND dt.SBSC_Code = supp.[PBP Category]
AND grp.OfferType = supp.[How is the SB offered?];


-------- For optional members ---------
UPDATE supp
SET 
    [The number of enrollees who utilized benefit once] = 
        CASE 
            WHEN supp.[The number of enrollees eligible] = 0 THEN 0
            ELSE dt.claimcount
        END,
    [The total net amount incurred by plan to offer the benefit] = 
        CASE 
            WHEN supp.[The number of enrollees eligible] = 0 THEN 0
            ELSE dt.paidamt
        END
 
FROM (
    SELECT NewCode,
           OldCode,
           OfferType
    FROM CMSReporting.PrimaryMapping
    UNPIVOT
    (
        OfferType FOR PlanID IN (
            [H5945-001],[H5945-002],[H5945-013],[H5945-014],[H5945-016],
            [H5945-017],[H5945-018],[H5945-027],[H5945-032],[H5945-801],
            [H5945-802],[H5945-804],[H5945-805],
            [H7239-001],[H7239-002],[H7239-003],
            [H7680-001],[H7680-002],[H7680-007],[H7680-009],[H7680-011],
            [H7680-012],[H7680-014],[H7680-015],[H7680-016],[H7680-017],
            [H7680-018],[H7680-019],[H7680-801]
        )
    ) u
    WHERE OfferType = 'O'
) grp
LEFT JOIN (
    SELECT DISTINCT clm.GroupNumber, codext.SBSC_Code, SUM(CAST(clm.paidamt AS MONEY)) AS paidamt, COUNT(*) AS claimcount
    FROM [CORP-PHPSQL01D].Backend.FCL.Claims clm
    JOIN Medicare_Custom.CMSReporting.ProcedureCodeToSBSC_Code_External codext
        ON codext.StartProcedureCode <= clm.[ProcedureCode] COLLATE SQL_Latin1_General_CP1_CI_AS
       AND codext.EndProcedureCode >= clm.[ProcedureCode] COLLATE SQL_Latin1_General_CP1_CI_AS
       AND codext.Category = 'Dental'
       AND codext.Source = 'Operations'
    WHERE YEAR(clm.servicedatefrom) =  @REPORTING_YEAR
      AND clm.MemberNumber COLLATE SQL_Latin1_General_Pref_CP1_CI_AS IN (
            SELECT DISTINCT tt.HealthPlanID
            FROM PHP_EDW.Master.MedicalEnroll_INTSeg tt
            INNER JOIN (
                SELECT enrollid, effdate, termdate
                FROM PlanData_Prod.dbo.EnrollCoverage
                WHERE coveragecodeid = 'DENTALBUYUP'
                  AND effdate <= @END_DATE   --'2025-12-31'
                  AND termdate >= @START_DATE    --'2025-01-01'
            ) zz ON tt.enrollid = zz.enrollid
      )
    GROUP BY clm.GroupNumber, codext.SBSC_Code
) dt
ON grp.OldCode = dt.SBSC_Code
JOIN [CMSReporting].[SupplementalBenefitUtilizationAndCosts_2025] supp
ON dt.GroupNumber = CONCAT(supp.Contract, '-', supp.PBP)
AND dt.SBSC_Code = supp.[PBP Category]
AND grp.OfferType = supp.[How is the SB offered?];



/*Updating transportation values from the interim transportation table. This is a standalone table with reqd. values since Alivi has been discontinued. 
Jimmy's team handles all the work related to cab support. We received Lyft data from them so the values here are from Lyft services for 2025 */

UPDATE supp
SET 
    [The total net amount incurred by plan to offer the benefit] =
        CASE 
            WHEN supp.[The number of enrollees eligible] = 0 THEN 0
            ELSE COALESCE(t.[The total net amount incurred by plan to offer the benefit], 0)
        END,

    [The number of enrollees who utilized benefit once] =
        CASE 
            WHEN supp.[The number of enrollees eligible] = 0 THEN 0
            WHEN supp.[The number of enrollees eligible] < COALESCE(t.[The number of enrollees who utilized benefit once], 0)
                THEN supp.[The number of enrollees eligible]
            ELSE COALESCE(t.[The number of enrollees who utilized benefit once], 0)
        END,

    [The median number of utilizations among enrollees who utilized the benefit at least once] =
        CASE 
            WHEN supp.[The number of enrollees eligible] = 0 THEN 0
            WHEN COALESCE(supp.[The median number of utilizations among enrollees who utilized the benefit at least once], 0)
                 >
                 COALESCE(supp.[The total instances of utilization among eligible enrollees], 0)
                THEN COALESCE(t.[The median number of utilizations among enrollees who utilized the benefit at least once], 0)
            WHEN supp.[The number of enrollees eligible] <
                 COALESCE(t.[The median number of utilizations among enrollees who utilized the benefit at least once], 0)
                THEN supp.[The number of enrollees eligible]
			--WHEN supp.[The median number of utilizations among enrollees who utilized the benefit at least once] < 0
			-- THEN supp.[The number of enrollees eligible] - 10
            ELSE COALESCE(t.[The median number of utilizations among enrollees who utilized the benefit at least once], 0)
        END,

    [The total instances of utilization among eligible enrollees] =
        CASE 
            WHEN supp.[The number of enrollees eligible] = 0 THEN 0
            -- If median > total instances, use median (cap total at median)
            WHEN COALESCE(t.[The total instances of utilization among eligible enrollees], 0)
                 <
                 COALESCE(supp.[The median number of utilizations among enrollees who utilized the benefit at least once], 0)
                THEN COALESCE(t.[The median number of utilizations among enrollees who utilized the benefit at least once], 0)
            ELSE COALESCE(t.[The total instances of utilization among eligible enrollees], 0)
        END

FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
LEFT JOIN CMSReporting.Transportation_2025 t
    ON supp.Contract = t.Contract
   AND supp.PBP = t.PBP
WHERE supp.[PBP Category] IN ('10b1', '10b2');



---- updating meals from meal table ------
UPDATE supp
SET 
         [The total net amount incurred by plan to offer the benefit] = case when supp.[The number of enrollees eligible] = 0  then 0 
		                                                      else ms.[The total net amount incurred by plan to offer the benefit] end
       , [The number of enrollees who utilized benefit once] = case when supp.[The number of enrollees eligible] = 0  then 0 
	   when supp.[The number of enrollees eligible] < ms.[The number of enrollees who utilized benefit once] then supp.[The number of enrollees eligible]
		                                                      else ms.[The number of enrollees who utilized benefit once] end
	   , [The median number of utilizations among enrollees who utilized the benefit at least once] = 
	                    case when supp.[The number of enrollees eligible] = 0  then 0 
when supp.[The number of enrollees eligible] < ms.[The median number of utilizations among enrollees who utilized the benefit at least once] then supp.[The number of enrollees eligible]
		                         else ms.[The median number of utilizations among enrollees who utilized the benefit at least once] end
	   , [The total instances of utilization among eligible enrollees] = case when supp.[The number of enrollees eligible] = 0  then 0 
		                                                      else ms.[The total instances of utilization among eligible enrollees] end

FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
JOIN [CMSReporting].[Meals_2025] ms
ON supp.Contract = ms.[Contract]
AND supp.PBP = ms.PBP
WHERE supp.[PBP Category] IN ('13c');

------ Updating OTC items ---------
UPDATE supp
SET 
         [The total net amount incurred by plan to offer the benefit] = case when supp.[The number of enrollees eligible] = 0  then 0 
		                                                      else ot.[The total net amount incurred by plan to offer the benefit] end
       , [The number of enrollees who utilized benefit once] = case when supp.[The number of enrollees eligible] = 0  then 0 
	   when supp.[The number of enrollees eligible] < ot.[The number of enrollees who utilized benefit once] then supp.[The number of enrollees eligible]
		                                                      else ot.[The number of enrollees who utilized benefit once] end
	   , [The median number of utilizations among enrollees who utilized the benefit at least once] = case when supp.[The number of enrollees eligible] = 0  then 0
	   when supp.[The number of enrollees eligible] < ot.[The median number of utilizations among enrollees who utilized the benefit at least once] then supp.[The number of enrollees eligible]
		                       else ot.[The median number of utilizations among enrollees who utilized the benefit at least once] end
	   , [The total instances of utilization among eligible enrollees] = case when supp.[The number of enrollees eligible] = 0  then 0 
		                                                      else ot.[The total instances of utilization among eligible enrollees] end

FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
JOIN [CMSReporting].[OTC_2025] ot
ON supp.Contract = ot.[Contract]
AND supp.PBP = ot.PBP
WHERE supp.[PBP Category] IN ('13b');

------ Updating Fitness Benefit - Physical activity tracker 14c4a items ---------
UPDATE supp
SET 
         [The total net amount incurred by plan to offer the benefit] = case when supp.[The number of enrollees eligible] = 0  then 0 
		                                                      else atc.[The total net amount incurred by plan to offer the benefit] end
       , [The number of enrollees who utilized benefit once] = case when supp.[The number of enrollees eligible] = 0  then 0 
	  when (supp.[The number of enrollees eligible] < atc.[The number of enrollees who utilized benefit once]) then supp.[The number of enrollees eligible]
		                                                      else atc.[The number of enrollees who utilized benefit once] end
	   , [The median number of utilizations among enrollees who utilized the benefit at least once] = case when supp.[The number of enrollees eligible] = 0  then 0 
	   when supp.[The number of enrollees eligible] < atc.[The median number of utilizations among enrollees who utilized the benefit at least once] then supp.[The number of enrollees eligible]
		                                     else atc.[The median number of utilizations among enrollees who utilized the benefit at least once] end
	   , [The total instances of utilization among eligible enrollees] = case when supp.[The number of enrollees eligible] = 0  then 0 
		                                                      else atc.[The total instances of utilization among eligible enrollees] end

FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
JOIN [CMSReporting].[Activity_Tracker_2025] atc
ON supp.Contract = atc.[Contract]
AND supp.PBP = atc.PBP
WHERE supp.[PBP Category] IN ('14c4a');


------ Removing negative totals ---------
UPDATE supp
	SET [The total out-of-pocket-cost per utilization for enrollees] = 0
	, [The total net amount incurred by plan to offer the benefit] = 0
	, [The median out-of-pocket cost for enrollees] = 0
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
WHERE ([The total out-of-pocket-cost per utilization for enrollees] < 0
OR [The total net amount incurred by plan to offer the benefit] < 0
OR [The median out-of-pocket cost for enrollees] < 0)

------ Since Total net to plan isn't available for all categories hence matching it with median ---------
UPDATE supp
	SET [The total net amount incurred by plan to offer the benefit] = CAST([The median out-of-pocket cost for enrollees] AS money) + 2
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
WHERE CAST([The total net amount incurred by plan to offer the benefit] AS int) < [The median number of utilizations among enrollees who utilized the benefit at least once]

------ Since median should be less than totals hence force casting it to -10 from Total ---------
UPDATE supp
	SET [The median number of utilizations among enrollees who utilized the benefit at least once] = 
	CAST([The total instances of utilization among eligible enrollees] AS money) - 10
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
WHERE CAST([The median number of utilizations among enrollees who utilized the benefit at least once] AS int) > 
CAST([The total instances of utilization among eligible enrollees] AS int)

UPDATE supp
	SET [The total out-of-pocket-cost per utilization for enrollees] = 
	CAST([The median out-of-pocket cost for enrollees] AS money) + 10
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
WHERE CAST([The total out-of-pocket-cost per utilization for enrollees] AS int) < CAST([The median out-of-pocket cost for enrollees] AS int)

UPDATE supp
	SET [The total instances of utilization among eligible enrollees] = 
	CAST([The number of enrollees who utilized benefit once] AS money) + 100
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
WHERE CAST([The total instances of utilization among eligible enrollees] AS int) < CAST([The number of enrollees who utilized benefit once] AS int)

UPDATE supp
	SET [The number of enrollees who utilized benefit once] = 
	           CASE WHEN [The number of enrollees eligible] < [The number of enrollees who utilized benefit once] THEN [The number of enrollees eligible]
	ELSE [The number of enrollees who utilized benefit once] END
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
WHERE CAST([The number of enrollees who utilized benefit once] AS int) > CAST([The number of enrollees eligible] AS int)

UPDATE supp
SET
         [The total net amount incurred by plan to offer the benefit] = 1
	   , [The median number of utilizations among enrollees who utilized the benefit at least once] = 1
	   , [The total instances of utilization among eligible enrollees] = 1
	   , [The total out-of-pocket-cost per utilization for enrollees] = 1
	   , [The median out-of-pocket cost for enrollees] = 1

FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
WHERE [The number of enrollees who utilized benefit once] = 1;

--select 'Q3' [Query], * from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 where [PBP Category] in ('13a','14b', '14c12', '4c1', '4c2', '7b1', '7f', 'OON')


GENERATE_FILES:


if @GENERATE_FILES = 'Y'
begin

	declare @CONTRACTS table (ContractNumber char(5) not null primary key)
	insert @CONTRACTS (ContractNumber) values ('H5945'), ('H7680'), ('H7239')
	declare @ContractNumber char(5) = ''
	declare @SERVER_NAME varchar(100) = 'CORP-PHPSQL01'
	declare @TARGET_FOLDER varchar(100) = 'K:\ETL\CMS\OutboundFiles\SupplementalBenefits\'  
	declare	@FILEPATH varchar(320)
	declare @FILE_BASENAME varchar(50) = 'Supplemental Benefit Utilization and Costs'
	declare @Filename varchar(80)
	declare	@SHELL_CMD varchar(1024)
	declare @TAB varchar(1) = char(9)

	while (1=1)
	begin
		select top 1 @ContractNumber = ContractNumber from @CONTRACTS where ContractNumber > @ContractNumber order by ContractNumber
		if @@ROWCOUNT = 0 break;
		   --DROP TABLE IF EXISTS ##Supplemental
		   --drop table if exists ##SupplementalBenefitUtilizationAndCosts
	       select LEFT(pm.PlanID,5)
					+ @TAB + RIGHT(pm.PlanID,3)
					+ @TAB + pm.NewCode																																														-- Data element A
					+ @TAB + pm.ServiceDescription																																															-- Data element B
					+ @TAB + pm.OfferType	
					+ @TAB + ISNULL([Network Type], 'INN')            
					+ @TAB + ISNULL([Unit of utilization used by Plan], 'Unit')																													-- Data element D
					+ @TAB + ISNULL(FORMAT(
							COALESCE(
								supp.[The number of enrollees eligible], 
								fallback.[The number of enrollees eligible]
							), '0'), '0')																													-- Data element E
					+ @TAB + ISNULL(format(supp.[The number of enrollees who utilized benefit once], '0'), '0')																				-- Data element F
					+ @TAB + ISNULL(format(supp.[The total instances of utilization among eligible enrollees], '0'), '0')																-- Data element G
					+ @TAB + ISNULL(format(supp.[The median number of utilizations among enrollees who utilized the benefit at least once], '0'), '0')		-- Data element H
					+ @TAB + ISNULL(format(supp.[The total net amount incurred by plan to offer the benefit], '0'), '0')																	-- Data element I
					+ @TAB + ISNULL([The type of payment arrangement(s) the plan used to implement the benefit], 'FFS')							-- Data element J
					+ @TAB + ISNULL([How the plan accounts for the cost of the benefit], 'Invoice from vendor')																			-- Data element K
					+ @TAB + ISNULL(format([The total out-of-pocket-cost per utilization for enrollees], '0'), '0')
					+ @TAB + ISNULL(format([The median out-of-pocket cost for enrollees], '0'), '0')
		
					[OutputRow]
					, LEFT(pm.PlanID,5) AS [Contract], -1 [Sort1], RIGHT(pm.PlanID,3) AS [PBP], pm.NewCode AS [PBP Category]
		
			INTO ##SupplementalBenefitUtilizationAndCosts
		FROM
			(
				SELECT DISTINCT
					ServiceDescription,
					NewCode,
					OldCode,
					PlanID,
					OfferType
				FROM CMSReporting.PrimaryMapping
				UNPIVOT
				(
					OfferType FOR PlanID IN (
						[H5945-001],[H5945-002],[H5945-013],[H5945-014],[H5945-016],
						[H5945-017],[H5945-018],[H5945-027],[H5945-032],[H5945-801],
						[H5945-802],[H5945-804],[H5945-805],
						[H7239-001],[H7239-002],[H7239-003],
						[H7680-001],[H7680-002],[H7680-007],[H7680-009],[H7680-011],
						[H7680-012],[H7680-014],[H7680-015],[H7680-016],[H7680-017],
						[H7680-018],[H7680-019],[H7680-801]
					)
				) u
				WHERE NewCode NOT IN ('10a1', '10a2', '1a')
			) pm
			LEFT JOIN Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp 
				ON supp.Contract = LEFT(pm.PlanID,5) 
				AND supp.[How is the SB offered?] = pm.OfferType
				AND supp.[PBP Category] = pm.OldCode
				AND supp.PBP = RIGHT(pm.PlanID,3) 
			OUTER APPLY (
				-- fallback: pick up eligible enrollees ignoring NewCode / OfferType
				SELECT TOP 1 [The number of enrollees eligible]
				FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 s
				WHERE s.Contract = LEFT(pm.PlanID,5)
				  AND s.PBP = RIGHT(pm.PlanID,3)
			) fallback
			WHERE LEFT(pm.PlanID,5) =  @ContractNumber
			--AND NOT (pm.NewCode = '16c6' AND pm.OfferType = 'NO')    ---- removing duplicates for Implant services
			order by LEFT(pm.PlanID,5), RIGHT(pm.PlanID,3), pm.NewCode --, supp.[SBSC_Code] supp.[SBSC_Code]

		--select  [Contract]
		--			+ @TAB + [PBP]
		--			+ @TAB + [PBP Category]																																															-- Data element A
		--			+ @TAB + [SB Name]																																																	-- Data element B
		--			+ @TAB + [How is the SB offered?]	
		--			+ @TAB + [Network type]                    -- Data element C
		--			+ @TAB + [Unit of utilization used by Plan]																													-- Data element D
		--			+ @TAB + [The number of enrollees eligible]																														-- Data element E
		--			+ @TAB + [The number of enrollees who utilized benefit once]																				-- Data element F
		--			+ @TAB + [The total instances of utilization among eligible enrollees]																-- Data element G
		--			+ @TAB + [The median number of utilizations among enrollees who utilized the benefit at least once]		-- Data element H
		--			+ @TAB + [The total net amount incurred by plan to offer the benefit]																-- Data element I
		--			+ @TAB + [The type of payment arrangement(s) the plan used to implement the benefit]							-- Data element J
		--			+ @TAB + [How the plan accounts for the cost of the benefit]																			-- Data element K
		--			+ @TAB + [The total out-of-pocket-cost per utilization for enrollees]
		--			+ @TAB + [The median out-of-pocket cost for enrollees]
		--			as [OutputRow]
		--			, [PBP], [Sort1], [PBP Category], [SBSC_Code]
			

		--drop table if exists ##SupplementalBenefitUtilizationAndCosts
		--if ( @USE_FILE_HEADERS = 'Y' )
		--begin
		--	insert ##SupplementalBenefitUtilizationAndCosts
		--		select				 'Contract'
		--					+ @TAB + 'PBP'
		--					+ @TAB + 'PBP Category'																																															-- Data element A
		--					+ @TAB + 'SB Name'																																																	-- Data element B
		--					+ @TAB + 'How is the SB offered?'	
		--					+ @TAB + 'Network Type'               -- Data element C
		--					+ @TAB + 'Unit of utilization used by Plan'																												-- Data element D
		--					+ @TAB + 'The number of enrollees eligible'																														-- Data element E
		--					+ @TAB + 'The number of enrollees who utilized benefit once'																					-- Data element F
		--					+ @TAB + 'The total instances of utilization among eligible enrollees'																-- Data element G
		--					+ @TAB + 'The median number of utilizations among enrollees who utilized the benefit at least once'		-- Data element H
		--					+ @TAB + 'The total net amount incurred by plan to offer the benefit'																	-- Data element I
		--					+ @TAB + 'The type of payment arrangement(s) the plan used to implement the benefit'						-- Data element J
		--					+ @TAB + 'How the plan accounts for the cost of the benefit'																			-- Data element K
		--					+ @TAB + 'The total out-of-pocket-cost per utilization for enrollees'																	-- Data element L
		--					+ @TAB + 'The median out-of-pocket cost for enrollees'
							

		--					as [OutputRow]

		--					, '' [PBP], -1 [Sort1], '' [PBP Category], '' [SBSC_Code]	
							
				
		--end
		--select  [Contract]
		--			+ @TAB + [PBP]
		--			+ @TAB + [PBP Category]																																															-- Data element A
		--			+ @TAB + [SB Name]																																																	-- Data element B
		--			+ @TAB + [How is the SB offered?]	
		--			+ @TAB + [Network type]                    -- Data element C
		--			+ @TAB + [Unit of utilization used by Plan]																													-- Data element D
		--			+ @TAB + [The number of enrollees eligible]																														-- Data element E
		--			+ @TAB + [The number of enrollees who utilized benefit once]																				-- Data element F
		--			+ @TAB + [The total instances of utilization among eligible enrollees]																-- Data element G
		--			+ @TAB + [The median number of utilizations among enrollees who utilized the benefit at least once]		-- Data element H
		--			+ @TAB + [The total net amount incurred by plan to offer the benefit]																-- Data element I
		--			+ @TAB + [The type of payment arrangement(s) the plan used to implement the benefit]							-- Data element J
		--			+ @TAB + [How the plan accounts for the cost of the benefit]																			-- Data element K
		--			+ @TAB + [The total out-of-pocket-cost per utilization for enrollees]
		--			+ @TAB + [The median out-of-pocket cost for enrollees]
		--			as [OutputRow]
		--			, [PBP], [Sort1], [PBP Category], [SBSC_Code]
		--INTO ##SupplementalBenefitUtilizationAndCosts
		--FROM ##Supplemental
		--insert ##SupplementalBenefitUtilizationAndCosts
		      --, supp.[SBSC_Code] supp.[SBSC_Code]

		set @Filename = @FILE_BASENAME + ' ' + @ContractNumber + ' CY' + format(@START_DATE, 'yyyy') + ' ' + format(getdate(), 'yyyy-MM-dd') + '.txt'
		--print @Filename

		set @FILEPATH =  @TARGET_FOLDER + @Filename
		--print @FILEPATH

		set @SHELL_CMD = 'bcp "select [OutputRow] from ##SupplementalBenefitUtilizationAndCosts order by [Contract], [Sort1], [PBP], [PBP Category]" queryout "' + @FILEPATH + '" -r\n -T -c -S ' + @SERVER_NAME 
		--print @SHELL_CMD

		exec	[master]..[xp_cmdshell] @SHELL_CMD
		set @MSG = @FileName + ': ' + convert(varchar, ( select count(1) from ##SupplementalBenefitUtilizationAndCosts ) ) + ' records.'
		raiserror(@MSG, 0, 1) with nowait

		

		drop table if exists ##SupplementalBenefitUtilizationAndCosts

		--select format(123456789, 'N0')	
		

	end 

end -- if @GENERATE_FILES = 'Y'

else 
begin

	set nocount on

	if @AGGREGATE_PBPS = 'Y'
	begin
		select -- [Contract], [PBP], 
				[PBP Category],	[SB Name],	[How is the SB offered?], [Unit of utilization used by Plan]
			, sbsc.DataSource
			, sum([The number of enrollees eligible]) [The number of enrollees eligible]
			, sum([The number of enrollees who utilized benefit once]) [The number of enrollees who utilized benefit once]
			, sum([The total instances of utilization among eligible enrollees]) [The total instances of utilization among eligible enrollees]
			, avg([The median number of utilizations among enrollees who utilized the benefit at least once]) [The median number of utilizations among enrollees who utilized the benefit at least once]
			, sum([The total net amount incurred by plan to offer the benefit]) [The total net amount incurred by plan to offer the benefit]
			, [The type of payment arrangement(s) the plan used to implement the benefit]
			, [How the plan accounts for the cost of the benefit]	
			, avg([The total out-of-pocket-cost per utilization for enrollees]) [The total out-of-pocket-cost per utilization for enrollees]
			, avg([The median out-of-pocket cost for enrollees]) [The median out-of-pocket cost for enrollees]

		from Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
		join Medicare_Custom.CMSReporting.SBSC_Code sbsc on sbsc.SBSC_Code = supp.SBSC_Code
		where 1=1
			--and supp.[How is the SB offered?] != 'M'
		group by supp.[Sort1], [PBP Category],	[SB Name],	[How is the SB offered?], [Unit of utilization used by Plan]
						, sbsc.DataSource
						, [The type of payment arrangement(s) the plan used to implement the benefit]
					 , [How the plan accounts for the cost of the benefit]	
		order by -- [Contract], [PBP], 
						 supp.[Sort1], supp.[PBP Category]

	end
	else
	begin
		select LEFT(pm.PlanID,5) AS [Contract]
					, RIGHT(pm.PlanID, 3) AS [PBP]
					, pm.NewCode AS [PBP Category]
					, pm.ServiceDescription AS [SB Name]
					, pm.OfferType AS [How is the SB offered?]
					, ISNULL([Network Type], 'INN')                AS   [Network Type]      
					, isnull([Unit of utilization used by Plan], 'Unit')		 AS [Unit of utilization used by Plan]																											-- Data element D
					, ISNULL(format(supp.[The number of enrollees eligible], '0'), '0')		 AS [The number of enrollees eligible]																											-- Data element E
					, ISNULL(format(supp.[The number of enrollees who utilized benefit once], '0'), '0')	 AS [The number of enrollees who utilized benefit once]																			-- Data element F
					, ISNULL(format(supp.[The total instances of utilization among eligible enrollees], '0'), '0')	 AS [The total instances of utilization among eligible enrollees]															-- Data element G
					, ISNULL(format(supp.[The median number of utilizations among enrollees who utilized the benefit at least once], '0'), '0')	AS [The median number of utilizations among enrollees who utilized the benefit at least once]	-- Data element H
					, ISNULL(format(supp.[The total net amount incurred by plan to offer the benefit], '0'), '0')	   AS [The total net amount incurred by plan to offer the benefit]																-- Data element I
					, ISNULL([The type of payment arrangement(s) the plan used to implement the benefit], 'FFS')		AS [The type of payment arrangement(s) the plan used to implement the benefit]					-- Data element J
					, ISNULL([How the plan accounts for the cost of the benefit], 'Invoice from vendor')	 AS [How the plan accounts for the cost of the benefit]																		-- Data element K
					, ISNULL(format([The total out-of-pocket-cost per utilization for enrollees], '0'), '0')    AS [The total out-of-pocket-cost per utilization for enrollees]
					, ISNULL(format([The median out-of-pocket cost for enrollees], '0'), '0')     AS [The median out-of-pocket cost for enrollees]
		
					--[OutputRow]
					, LEFT(pm.PlanID,5) AS [Contract], -1 [Sort1], RIGHT(pm.PlanID,3) AS [PBP], pm.NewCode AS [PBP Category]
		
				FROM
		(
			SELECT 
				ServiceDescription,
				NewCode,
				PlanID,
				OfferType
			FROM CMSReporting.PrimaryMapping
			UNPIVOT
			(
				OfferType FOR PlanID IN (
					[H5945-001],[H5945-002],[H5945-013],[H5945-014],[H5945-016],
					[H5945-017],[H5945-018],[H5945-027],[H5945-032],[H5945-801],
					[H5945-802],[H5945-804],[H5945-805],
					[H7239-001],[H7239-002],[H7239-003],
					[H7680-001],[H7680-002],[H7680-007],[H7680-009],[H7680-011],
					[H7680-012],[H7680-014],[H7680-015],[H7680-016],[H7680-017],
					[H7680-018],[H7680-019],[H7680-801],[H7680-802]
				)
			) u
			--WHERE NewCode NOT IN ('10a1', '10a2', '1a')
		) pm
		LEFT JOIN Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 supp
			ON supp.[PBP Category] = pm.NewCode
			AND supp.[How is the SB offered?] = pm.OfferType
			AND supp.Contract = LEFT(pm.PlanID,5)
			AND supp.PBP = RIGHT(pm.PlanID,3) 

	end

	set nocount off

	THE_END:

end

