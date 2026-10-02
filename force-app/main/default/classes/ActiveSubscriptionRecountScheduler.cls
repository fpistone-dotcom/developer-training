/**
 * @description DEV #4: el "despertador" del recuento nocturno. Salesforce lo ejecuta todas las
 *              noches a las 2:00 (una hora después del job del DEV #1, para no coincidir) y solo
 *              lanza ActiveSubscriptionRecountBatch, sin lógica propia.
 *
 *              Para programarlo (una sola vez, por ejemplo desde Execute Anonymous):
 *              System.schedule( ActiveSubscriptionRecountScheduler.JOB_NAME,
 *                               ActiveSubscriptionRecountScheduler.CRON_EXPRESSION,
 *                               new ActiveSubscriptionRecountScheduler() );
 */
public with sharing class ActiveSubscriptionRecountScheduler implements Schedulable {

    public static final String JOB_NAME = 'Active Subscriptions Recount - Nightly';

    // Segundo Minuto Hora Día-del-mes Mes Día-de-la-semana: todos los días a las 2:00
    public static final String CRON_EXPRESSION = '0 0 2 * * ?';

    /**
     * @description Lo llama Salesforce a la hora programada. Solo lanza el Batch.
     * @param sc Contexto del job programado (lo pasa Salesforce)
     */
    public void execute( SchedulableContext sc ) {
        Database.executeBatch( new ActiveSubscriptionRecountBatch() );
    }
}
