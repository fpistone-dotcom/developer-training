/**
 * @description Tests del DEV #1 (Parte B): QuoteExpirationScheduler.
 *              En un test, Test.stopTest() ejecuta el job programado en el momento, sin
 *              esperar a la hora del cron.
 */
@IsTest
private class QuoteExpirationSchedulerTest {

    /**
     * @description El job queda programado con el cron nocturno y, al ejecutarse, lanza
     *              QuoteExpirationBatch.
     */
    @isTest
    static void scheduleNightlyJobTest() {
        Test.startTest();
        Id jobId = System.schedule( QuoteExpirationScheduler.JOB_NAME,
            QuoteExpirationScheduler.CRON_EXPRESSION, new QuoteExpirationScheduler() );
        Test.stopTest(); // acá corre el execute() del Scheduler

        CronTrigger scheduledJob = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals( QuoteExpirationScheduler.CRON_EXPRESSION, scheduledJob.CronExpression,
            'El job debería quedar programado para todas las noches a la 1:00' );

        Integer batchJobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'QuoteExpirationBatch'
        ];
        System.assertEquals( 1, batchJobCount, 'El Scheduler debería lanzar QuoteExpirationBatch' );
    }
}
