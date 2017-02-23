/*
Copyright 2017 Dirk Strack

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

------------------------------------------------------------------------------
Plugin for checking that a table row is deletable.

- Plugin Callbacks:
- Execution Function Name: delete_check_plugin.Process_Row_Is_Deletable
	attribute_01 : Table Owner
	attribute_02 : *Table Name
	attribute_03 : *Primary Key Column
	attribute_04 : *Primary Key Item
	attribute_05 : Secondary Key Column
	attribute_06 : Secondary Key Item
	attribute_07 : *Is Deletable Item

*/

DROP MATERIALIZED VIEW MV_DELETE_CHECK;

CREATE MATERIALIZED VIEW MV_DELETE_CHECK
AS
	SELECT A.R_OWNER1 R_OWNER,
		A.R_TABLE_NAME1 R_TABLE_NAME,
		' from ' || DBMS_ASSERT.ENQUOTE_NAME(A.R_OWNER1) || '.' || DBMS_ASSERT.ENQUOTE_NAME(A.R_TABLE_NAME1) || ' A ' || chr(10) || 'WHERE NOT EXISTS '
		|| LISTAGG(A.SUBQ, chr(10) || '  and not exists ') WITHIN GROUP (ORDER BY A.R_CONSTRAINT_NAME1, A.TABLE_NAME) SUBQ
	FROM (
			SELECT
				CONNECT_BY_ROOT R_CONSTRAINT_NAME R_CONSTRAINT_NAME1,
				CONNECT_BY_ROOT R_OWNER R_OWNER1,
				CONNECT_BY_ROOT R_TABLE_NAME R_TABLE_NAME1,
				OWNER,
				TABLE_NAME,
				DELETE_RULE,
				SYS_CONNECT_BY_PATH(
					'select 1 from ' || DBMS_ASSERT.ENQUOTE_NAME(A.OWNER) || '.' || DBMS_ASSERT.ENQUOTE_NAME(A.TABLE_NAME) || ' ' || CHR(65+LEVEL)
					|| ' where ' || REPLACE(REPLACE(JOIN_COND, 'X.', CHR(65+LEVEL-1)||'.'), 'Y.', CHR(65+LEVEL)||'.')
					|| CASE WHEN CONNECT_BY_ISLEAF = 0 THEN ' and exists ' END,
					'('
				) || LPAD(')', LEVEL, ')') SUBQ
			FROM (
				SELECT A.CONSTRAINT_NAME, A.OWNER, A.TABLE_NAME, A.DELETE_RULE,
					C.CONSTRAINT_NAME R_CONSTRAINT_NAME, C.OWNER R_OWNER, C.TABLE_NAME R_TABLE_NAME,
					LISTAGG('Y.' || DBMS_ASSERT.ENQUOTE_NAME(B.COLUMN_NAME) || ' = ' || 'X.' || DBMS_ASSERT.ENQUOTE_NAME(D.COLUMN_NAME), ' AND ')
						WITHIN GROUP (ORDER BY B.POSITION) JOIN_COND
				FROM SYS.ALL_CONSTRAINTS A
				JOIN SYS.ALL_CONSTRAINTS C ON A.R_CONSTRAINT_NAME = C.CONSTRAINT_NAME AND C.OWNER = A.OWNER
				JOIN SYS.ALL_CONS_COLUMNS B ON A.CONSTRAINT_NAME = B.CONSTRAINT_NAME AND A.OWNER = B.OWNER
				JOIN SYS.ALL_CONS_COLUMNS D ON C.CONSTRAINT_NAME = D.CONSTRAINT_NAME AND C.OWNER = D.OWNER AND B.POSITION = D.POSITION
				WHERE A.CONSTRAINT_TYPE = 'R'
				AND INSTR(A.OWNER, 'SYS') = 0
				AND A.STATUS = 'ENABLED'
				AND C.CONSTRAINT_TYPE IN ('P', 'U')
				AND C.STATUS = 'ENABLED'
				GROUP BY A.CONSTRAINT_NAME, A.OWNER, A.TABLE_NAME, A.DELETE_RULE, C.CONSTRAINT_NAME, C.OWNER, C.TABLE_NAME
			) A
			WHERE CONNECT_BY_ISLEAF = 1 AND A.DELETE_RULE = 'NO ACTION'
			CONNECT BY NOCYCLE R_TABLE_NAME = PRIOR TABLE_NAME AND PRIOR DELETE_RULE = 'CASCADE'
	) A
	GROUP BY A.R_OWNER1, A.R_TABLE_NAME1
ORDER BY A.R_OWNER1, A.R_TABLE_NAME1;

ALTER  TABLE MV_DELETE_CHECK ADD
 CONSTRAINT MV_DELETE_CHECK_UK UNIQUE (R_OWNER, R_TABLE_NAME) USING INDEX;


-- SELECT * FROM MV_DELETE_CHECK WHERE R_TABLE_NAME = 'EMPLOYEES' AND R_OWNER = 'HR';

CREATE OR REPLACE PACKAGE delete_check_plugin
AUTHID CURRENT_USER
IS
	TYPE cur_type IS REF CURSOR;

	PROCEDURE Refresh_Mv_Delete_Check;

	PROCEDURE Refresh_Mv_Delete_Check_Job (
		p_Next_Date DATE DEFAULT SYSDATE,
		p_Hours INTEGER DEFAULT 1,
		p_Active INTEGER DEFAULT 1
	);

	FUNCTION Row_Is_Deletable(
		p_Owner IN VARCHAR2 DEFAULT USER,
		p_Table_Name IN VARCHAR2,
		p_PKCol_Name IN VARCHAR2,
		p_PKCol_Value IN VARCHAR2,
		p_PKCol_Name2 IN VARCHAR2 DEFAULT NULL,
		p_PKCol_Value2 IN VARCHAR2 DEFAULT NULL
	)
	RETURN NUMBER;

	FUNCTION Process_Row_Is_Deletable (
		p_process in apex_plugin.t_process,
		p_plugin  in apex_plugin.t_plugin )
	RETURN apex_plugin.t_process_exec_result;
END delete_check_plugin;
/
show errors

CREATE OR REPLACE PACKAGE BODY delete_check_plugin
IS
	PROCEDURE Refresh_Mv_Delete_Check
	IS
	BEGIN -- run DBMS_MVIEW.REFRESH with invoker rights
		EXECUTE IMMEDIATE 'SET ROLE ALL';
		DBMS_MVIEW.REFRESH('MV_DELETE_CHECK');
	END;

	PROCEDURE Refresh_Mv_Delete_Check_Job (
		p_Next_Date DATE DEFAULT SYSDATE,
		p_Hours INTEGER DEFAULT 1,
		p_Active INTEGER DEFAULT 1
	)
	IS
		v_jobno    NUMBER;
		v_what VARCHAR2(200) := 'delete_check_plugin.Refresh_Mv_Delete_Check;';
	BEGIN
		begin
			SELECT JOB
			INTO v_jobno
			FROM USER_JOBS
			WHERE WHAT = v_what;

			DBMS_JOB.REMOVE(v_JOBNO);
		exception
		  when NO_DATA_FOUND then
			v_jobno := NULL;
		end;
		if p_Active <> 0 then
			DBMS_JOB.SUBMIT(
				job 		=> v_jobno,
				what 		=> v_what,
				next_date 	=> p_Next_Date,
				interval 	=> 'SYSDATE + INTERVAL ' || DBMS_ASSERT.ENQUOTE_LITERAL(p_Hours) || ' HOUR'
			);
			COMMIT;
			DBMS_OUTPUT.PUT_LINE('Job No ' || v_jobno || ' has been created');
		end if;
	END;

	FUNCTION Row_Is_Deletable(
		p_Owner IN VARCHAR2 DEFAULT USER,
		p_Table_Name IN VARCHAR2,
		p_PKCol_Name IN VARCHAR2,
		p_PKCol_Value IN VARCHAR2,
		p_PKCol_Name2 IN VARCHAR2 DEFAULT NULL,
		p_PKCol_Value2 IN VARCHAR2 DEFAULT NULL
	)
	RETURN NUMBER
	IS
		TYPE cur_type IS REF CURSOR;
		subq_cur    cur_type;
		cnt_cur     cur_type;
		v_Result NUMBER := 1;
		v_Subquery VARCHAR2(32767);
	BEGIN
		if p_PKCol_Value IS NULL then
			-- when primary key value is null the row is not deletable
			return 0;
		end if;
		-- load query for drill down to dependent child rows with a foreign key to the main table primary key.
		OPEN subq_cur FOR
			SELECT SUBQ
			FROM MV_DELETE_CHECK
			WHERE R_OWNER = UPPER(p_Owner)
			AND R_TABLE_NAME = p_Table_Name;
		FETCH subq_cur INTO v_Subquery;
		if subq_cur%FOUND then
			-- when a child query was found, execute it with the given parameters.
			if P_PKCol_Name2 IS NOT NULL then
				v_Subquery := 'SELECT 1 ' || v_Subquery || chr(10) || '  AND ' || p_PKCol_Name || ' = :a AND ' || p_PKCol_Name2 || ' = :b ';
				if apex_application.g_debug then
					apex_debug.info('Executing child query:');
					apex_debug.info(v_Subquery || ' -- using %s, %s', p_PKCol_Value, p_PKCol_Value2);
				end if;
				-- DBMS_OUTPUT.PUT_LINE(v_Subquery || ' using ' || p_PKCol_Value || ', ' || p_PKCol_Value2);
				OPEN cnt_cur FOR v_Subquery USING p_PKCol_Value, p_PKCol_Value2;
			else
				v_Subquery := 'SELECT 1 ' || v_Subquery || chr(10) || '  AND ' || p_PKCol_Name || ' = :a ';
				if apex_application.g_debug then
					apex_debug.info('executing child query:');
					apex_debug.info(v_Subquery || ' -- using %s', p_PKCol_Value);
				end if;
				-- DBMS_OUTPUT.PUT_LINE(v_Subquery || ' using ' || p_PKCol_Value);
				OPEN cnt_cur FOR v_Subquery USING p_PKCol_Value;
			end if;
			FETCH cnt_cur INTO v_Result;
			-- when the execution of the child query delivered a row, then the test passed and the row is deletable.
			if cnt_cur%NOTFOUND then
				if apex_application.g_debug then
					apex_debug.info('Dependent child row was found, row is not deletable.');
				end if;
				v_Result := 0;
			else
				if apex_application.g_debug then
					apex_debug.info('No dependent child row was found, row is deletable.');
				end if;
				v_Result := 1;
			end if;
			CLOSE cnt_cur;
		else
			-- when not query was found, then the row is deletable.
			if apex_application.g_debug then
				apex_debug.info('not child query was found, row is deletable.');
			end if;
		end if;
		CLOSE subq_cur;

		RETURN v_Result;
	END Row_Is_Deletable;

	FUNCTION Process_Row_Is_Deletable (
		p_process in apex_plugin.t_process,
		p_plugin  in apex_plugin.t_plugin )
	RETURN apex_plugin.t_process_exec_result
	IS
		v_exec_result apex_plugin.t_process_exec_result;
		v_Table_Owner			VARCHAR2(50);
		v_Table_Name			VARCHAR2(50);
		v_Primary_Key_Column	VARCHAR2(50);
		v_Primary_Key_Item		VARCHAR2(50);
		v_Primary_Key_Value		VARCHAR2(500);
		v_Secondary_Key_Column	VARCHAR2(50);
		v_Secondary_Key_Item	VARCHAR2(50);
		v_Secondary_Key_Value	VARCHAR2(500);
		v_Is_Deletable_Item		VARCHAR2(50);
		v_Is_Deletable			VARCHAR2(50);
		v_Result 				NUMBER;
	BEGIN
		if apex_application.g_debug then
			apex_plugin_util.debug_process (
				p_plugin => p_plugin,
				p_process => p_process
			);
		end if;
		v_Table_Owner 			:= NVL(p_process.attribute_01, apex_application.g_flow_owner);
		v_Table_Name 			:= p_process.attribute_02;
		v_Primary_Key_Column	:= p_process.attribute_03;
		v_Primary_Key_Item		:= p_process.attribute_04;
		v_Primary_Key_Value		:= APEX_UTIL.GET_SESSION_STATE(v_Primary_Key_Item);
		v_Secondary_Key_Column	:= p_process.attribute_05;
		v_Secondary_Key_Item	:= p_process.attribute_06;
		v_Secondary_Key_Value	:= case when v_Secondary_Key_Item IS NOT NULL then APEX_UTIL.GET_SESSION_STATE(v_Secondary_Key_Item) end;
		v_Is_Deletable_Item		:= p_process.attribute_07;

        if apex_application.g_debug then
            apex_debug.info('Table_Owner          : %s', v_Table_Owner);
            apex_debug.info('Table_Name           : %s', v_Table_Name);
            apex_debug.info('Primary_Key_Column   : %s', v_Primary_Key_Column);
            apex_debug.info('Primary_Key_Item     : %s', v_Primary_Key_Item);
            apex_debug.info('Primary_Key_Value    : %s', v_Primary_Key_Value);
            apex_debug.info('Secondary_Key_Column : %s', v_Secondary_Key_Column);
            apex_debug.info('Secondary_Key_Item   : %s', v_Secondary_Key_Item);
            apex_debug.info('Secondary_Key_Value  : %s', v_Secondary_Key_Value);
        end if;
		v_Result := delete_check_plugin.Row_Is_Deletable (
			p_Owner 		=> v_Table_Owner,
			p_Table_Name	=> v_Table_Name,
			p_PKCol_Name	=> v_Primary_Key_Column,
			p_PKCol_Value	=> v_Primary_Key_Value,
			p_PKCol_Name2	=> v_Secondary_Key_Column,
			p_PKCol_Value2	=> v_Secondary_Key_Value
		);
		v_Is_Deletable := case when v_Result = 0 then 'N' else 'Y' end;
		apex_util.set_session_state(v_Is_Deletable_Item, v_Is_Deletable);
		RETURN v_exec_result;
	END Process_Row_Is_Deletable;

END delete_check_plugin;
/
show errors

-- SELECT delete_check_plugin.Row_Is_Deletable(p_Owner=>'SH', p_Table_Name=>'CUSTOMERS', P_PKCol_Name=>'CUST_ID', p_PKCol_Value=>'24540') Row_Is_Deletable FROM DUAL;

begin
	delete_check_plugin.Refresh_Mv_Delete_Check_Job;
end;
/
