README:

Oracle Apex Plug-in for checking that a table row is deletable.

When you encounter the ORA-02292 error when you attempt to delete a row
then use this plugin to hide the delete button.

In case you have created a page of type 'DML Form' with a 'Delete' Button, then this button is shown for each existing row.
When the application user tries to delete a row that is referenced directly or indirectly in a child table
by a foreign key with a delete_rule of 'NO ACTION',
then the system will return an "ORA-02292: integrity constraint <constraint name> violated - child record found" error message.

Now you can use this plugin to hide the delete button when a table row can not be deleted.

You have to create a hidden Page Item PXX_IS_DELETABLE.
The PXX_IS_DELETABLE has to be selected in the 'Is Deletable Item' attribute of the plugin.

Next step: change the 'Condition' of the DELETE button
Set 'Condition Type' to 'Value of Item / Column in Expression 1 = Expression2'
Set 'Expression 1' to PXX_IS_DELETABLE
Set 'Expression 2' to Y

Next create a new page process.
Set 'Process Type' to  'Plug-ins'.
Set 'Select Plug-in' to 'Row Is Deletable Check'.
Set 'Name' to 'Row Is Deletable Check'.
Set 'Sequence' to 30 for example - after the 'Automatic Row Fetch' process.
Set 'Point' to "On Load - After Header".

Now edit the settings of the plugin instance.
Set the mandantory attributes 'Table Name', 'Primary Key Column', 'Primary Key Item'
to the same values that are used in the "Automatic Row Fetch" process.

Set the  attribute 'Is Deletable Item'. Enter the page item to receive the check result.
You can type in the name or pick from the list of available items. (for example: P2_IS_DELETABLE)
When the Plug-In is processed, the page item is set to Y when the current row is deletable, otherwise it is set to N.

--------
Installation:

* To install the apex plugin navigate to Shared Components / Plug-ins and import the file 
process_type_plugin_com_strack-software_delete_check.sql

* The package DELETE_CHECK_PLUGIN, the view V_DELETE_CHECK and the table PLUGIN_DELETE_CHECKS 
have to be installed in the application schema. 
execute the file delete_check_plsql_code.sql to install the required database objects.
You can add the file to the installation script of you application.

* You have to load the table PLUGIN_DELETE_CHECKS in an development environment where you can 
access the system catalog tables, that are used in the view V_DELETE_CHECK:
`
INSERT INTO PLUGIN_DELETE_CHECKS (R_OWNER, R_TABLE_NAME, SUBQUERY)
SELECT R_OWNER, R_TABLE_NAME, SUBQUERY FROM V_DELETE_CHECK;
COMMIT;
`
* In order to use the plugin in an Workspace where you can not access the system catalog tables,
add INSERT statements to an install script that is uploaded for your application.
With Oracle SQL Developer you can produce the INSERT statements to populate the table PLUGIN_DELETE_CHECKS.
`
SELECT /*insert*/ R_TABLE_NAME, SUBQUERY FROM PLUGIN_DELETE_CHECKS WHERE R_OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
`
--------

Regards
Dirk Strack

