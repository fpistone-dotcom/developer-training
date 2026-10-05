/**
 * @description Tests del DEV #3 (Parte 2): RenewalQuoteScheduler.
 *              En un test, Test.stopTest() ejecuta el job programado en el momento, sin
 *              esperar a la hora del cron.
 */
@IsTest
private class RenewalQuoteSchedulerTest {

    /**
     * @description El job queda programado con el cron nocturno y, al ejecutarse, lanza
     *              RenewalQuoteBatch.
     */
    @isTest
    static void scheduleNightlyJobTest() {
        // Los jobs programados NO se aíslan en los tests: si el job real ya existe con JOB_NAME,
        // Salesforce no permite otro con el mismo nombre. Por eso el test usa un nombre propio.
        String testJobName = RenewalQuoteScheduler.JOB_NAME + ' (Test)';

        Test.startTest();
        Id jobId = System.schedule( testJobName,
            RenewalQuoteScheduler.CRON_EXPRESSION, new RenewalQuoteScheduler() );
        Test.stopTest(); // acá corre el execute() del Scheduler

        CronTrigger scheduledJob = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals( RenewalQuoteScheduler.CRON_EXPRESSION, scheduledJob.CronExpression,
            'El job debería quedar programado para todas las noches a las 3:00' );

        Integer batchJobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'RenewalQuoteBatch'
        ];
        System.assertEquals( 1, batchJobCount, 'El Scheduler debería lanzar RenewalQuoteBatch' );
    }
}
