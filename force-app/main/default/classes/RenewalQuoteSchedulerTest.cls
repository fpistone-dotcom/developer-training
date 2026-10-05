/**
 * @description Tests for DEV #3 (Part 2): RenewalQuoteScheduler.
 *              In a test, Test.stopTest() runs the scheduled job right away, without
 *              waiting for the cron time.
 */
@IsTest
private class RenewalQuoteSchedulerTest {

    /**
     * @description The job is scheduled with the nightly cron and, when it runs, it launches
     *              RenewalQuoteBatch.
     */
    @isTest
    static void scheduleNightlyJobTest() {
        // Scheduled jobs are NOT isolated in tests: if the real job already exists with JOB_NAME,
        // Salesforce does not allow another one with the same name. That is why the test uses its own name.
        String testJobName = RenewalQuoteScheduler.JOB_NAME + ' (Test)';

        Test.startTest();
        Id jobId = System.schedule( testJobName,
            RenewalQuoteScheduler.CRON_EXPRESSION, new RenewalQuoteScheduler() );
        Test.stopTest(); // the Scheduler execute() runs here

        CronTrigger scheduledJob = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals( RenewalQuoteScheduler.CRON_EXPRESSION, scheduledJob.CronExpression,
            'The job should be scheduled for every night at 3:00' );

        Integer batchJobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'RenewalQuoteBatch'
        ];
        System.assertEquals( 1, batchJobCount, 'The Scheduler should launch RenewalQuoteBatch' );
    }
}
