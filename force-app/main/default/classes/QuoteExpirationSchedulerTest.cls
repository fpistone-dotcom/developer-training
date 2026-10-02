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
        // Los jobs programados NO se aíslan en los tests: el job real del org ya existe con
        // JOB_NAME, y Salesforce no permite dos jobs con el mismo nombre. Por eso el test usa
        // un nombre propio.
        String testJobName = QuoteExpirationScheduler.JOB_NAME + ' (Test)';

        Test.startTest();
        Id jobId = System.schedule( testJobName,
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
