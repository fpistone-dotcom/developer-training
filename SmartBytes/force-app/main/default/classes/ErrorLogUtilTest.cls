/**
 * @description Tests for ErrorLogUtil: build logs, save them with a single insert, and log the
 *              failed records of a Database.update (saveLogsForFailedResults).
 */
@IsTest
private class ErrorLogUtilTest {

    /**
     * @description Positive: the logs built with buildLog are saved with their data.
     */
    @isTest
    static void saveLogsTest() {
        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        errorLogList.add( ErrorLogUtil.buildLog( 'SomeClass', null, 'First error' ) );
        errorLogList.add( ErrorLogUtil.buildLog( 'SomeClass', null, 'Second error' ) );

        Test.startTest();
        ErrorLogUtil.saveLogs( errorLogList );
        Test.stopTest();

        // WITH SYSTEM_MODE: the test checks the log without depending on the permissions of the user running the test
        List<Error_Log__c> savedLogList = [
            SELECT Class_Name__c, Error_Message__c
            FROM Error_Log__c
            WITH SYSTEM_MODE
        ];
        System.assertEquals( 2, savedLogList.size(), 'The 2 logs should be saved' );

        // Long Text fields cannot be sorted in SOQL, so we collect the messages in a Set
        Set<String> savedMessageSet = new Set<String>();
        for ( Error_Log__c savedLog : savedLogList ) {
            System.assertEquals( 'SomeClass', savedLog.Class_Name__c, 'The log should store the class name' );
            savedMessageSet.add( savedLog.Error_Message__c );
        }
        System.assert( savedMessageSet.contains( 'First error' ), 'The first message should be saved' );
        System.assert( savedMessageSet.contains( 'Second error' ), 'The second message should be saved' );
    }

    /**
     * @description Negative: with an empty list no insert is done and nothing fails.
     */
    @isTest
    static void saveLogsEmptyListTest() {
        Test.startTest();
        ErrorLogUtil.saveLogs( new List<Error_Log__c>() );
        Test.stopTest();

        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'With an empty list nothing should be saved' );
    }

    /**
     * @description Positive: a real update that fails (an Account without Name) creates one log
     *              with the class, the Id of the failed record, the prefix and the StatusCode.
     *              The record that saved successfully does not create a log.
     */
    @isTest
    static void saveLogsForFailedResultsTest() {
        List<Account> accountList = new List<Account>{ new Account( Name = 'Valid' ), new Account( Name = 'Will fail' ) };
        insert accountList;
        // Name is required: the second update fails with REQUIRED_FIELD_MISSING
        accountList[1].Name = null;

        Test.startTest();
        List<Database.SaveResult> saveResultList = Database.update( accountList, false );
        ErrorLogUtil.saveLogsForFailedResults( saveResultList, accountList, 'SomeClass', 'Account update failed: ' );
        Test.stopTest();

        List<Error_Log__c> savedLogList = [
            SELECT Class_Name__c, Record_Id__c, Error_Message__c
            FROM Error_Log__c
            WITH SYSTEM_MODE
        ];
        System.assertEquals( 1, savedLogList.size(), 'Only the failed record should create a log' );
        System.assertEquals( 'SomeClass', savedLogList[0].Class_Name__c, 'The log should store the class name' );
        System.assertEquals( accountList[1].Id, savedLogList[0].Record_Id__c,
            'The log should point to the failed record, found by its position in the list' );
        System.assert( savedLogList[0].Error_Message__c.startsWith( 'Account update failed: REQUIRED_FIELD_MISSING - ' ),
            'The message should have the prefix and the StatusCode, but was: ' + savedLogList[0].Error_Message__c );
    }

    /**
     * @description Negative: if every record is saved successfully, no log is created.
     */
    @isTest
    static void saveLogsForFailedResultsAllSuccessTest() {
        List<Account> accountList = new List<Account>{ new Account( Name = 'Valid' ) };
        insert accountList;
        accountList[0].Name = 'Still valid';

        Test.startTest();
        List<Database.SaveResult> saveResultList = Database.update( accountList, false );
        ErrorLogUtil.saveLogsForFailedResults( saveResultList, accountList, 'SomeClass', 'Account update failed: ' );
        Test.stopTest();

        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'Successful saves should not create logs' );
    }
}
