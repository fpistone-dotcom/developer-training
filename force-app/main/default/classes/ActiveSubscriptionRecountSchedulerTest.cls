/**
 * @description Tests del DEV #4: ActiveSubscriptionRecountScheduler.
 *              En un test, Test.stopTest() ejecuta el job programado en el momento, sin
 *              esperar a la hora del cron.
 */
@IsTest
private class ActiveSubscriptionRecountSchedulerTest {

    /**
     * @description El job queda programado a las 2:00 y, al ejecutarse, lanza
     *              ActiveSubscriptionRecountBatch.
     */
    @isTest
    static void scheduleNightlyJobTest() {
        // Los jobs programados NO se aíslan en los tests: el job real del org ya existe con
        // JOB_NAME, y Salesforce no permite dos jobs con el mismo nombre. Por eso el test usa
        // un nombre propio.
        String testJobName = ActiveSubscriptionRecountScheduler.JOB_NAME + ' (Test)';

        Test.startTest();
        Id jobId = System.schedule( testJobName,
            ActiveSubscriptionRecountScheduler.CRON_EXPRESSION, new ActiveSubscriptionRecountScheduler() );
        Test.stopTest(); // acá corre el execute() del Scheduler

        CronTrigger scheduledJob = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals( '0 0 2 * * ?', scheduledJob.CronExpression,
            'El job debería quedar programado para todas las noches a las 2:00' );

        Integer batchJobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'ActiveSubscriptionRecountBatch'
        ];
        System.assertEquals( 1, batchJobCount, 'El Scheduler debería lanzar ActiveSubscriptionRecountBatch' );
    }
}
