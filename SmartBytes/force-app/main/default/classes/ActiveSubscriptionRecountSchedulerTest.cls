/**
 * @description Tests for DEV #4: ActiveSubscriptionRecountScheduler.
 *              In a test, Test.stopTest() runs the scheduled job right away, without
 *              waiting for the cron time.
 */
@IsTest
private class ActiveSubscriptionRecountSchedulerTest {

    /**
     * @description The job is scheduled at 2:00 and, when it runs, it launches
     *              ActiveSubscriptionRecountBatch.
     */
    @isTest
    static void scheduleNightlyJobTest() {
        // Scheduled jobs are NOT isolated in tests: the real org job already exists with
        // JOB_NAME, and Salesforce does not allow two jobs with the same name. That is why the
        // test uses its own name.
        String testJobName = ActiveSubscriptionRecountScheduler.JOB_NAME + ' (Test)';

        Test.startTest();
        Id jobId = System.schedule( testJobName,
            ActiveSubscriptionRecountScheduler.CRON_EXPRESSION, new ActiveSubscriptionRecountScheduler() );
        Test.stopTest(); // the Scheduler execute() runs here

        CronTrigger scheduledJob = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        // Literal value on purpose: comparing against CRON_EXPRESSION would compare the constant
        // with itself and would not detect a wrong cron in the class
        System.assertEquals( '0 0 2 * * ?', scheduledJob.CronExpression,
            'The job should be scheduled for every night at 2:00' );

        Integer batchJobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'ActiveSubscriptionRecountBatch'
        ];
        System.assertEquals( 1, batchJobCount, 'The Scheduler should launch ActiveSubscriptionRecountBatch' );
    }
}
