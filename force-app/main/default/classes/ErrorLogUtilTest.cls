/**
 * @description Tests for ErrorLogUtil: build logs and save them with a single insert.
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
}
