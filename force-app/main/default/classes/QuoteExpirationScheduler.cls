/**
 * @description Parte B del DEV #1: el "despertador" del proceso nocturno. Salesforce lo
 *              ejecuta todas las noches y solo lanza QuoteExpirationBatch, sin lógica propia
 *              (la lógica vive en el Batch).
 *
 *              Para programarlo (una sola vez, por ejemplo desde Execute Anonymous):
 *              System.schedule( QuoteExpirationScheduler.JOB_NAME,
 *                               QuoteExpirationScheduler.CRON_EXPRESSION,
 *                               new QuoteExpirationScheduler() );
 *              El job corre como el usuario que lo programa (tiene que ser un admin, porque
 *              hace recall de aprobaciones enviadas por otros usuarios).
 */
public with sharing class QuoteExpirationScheduler implements Schedulable {

    public static final String JOB_NAME = 'Quote Expiration Recall - Nightly';

    // Segundo Minuto Hora Día-del-mes Mes Día-de-la-semana: todos los días a la 1:00
    public static final String CRON_EXPRESSION = '0 0 1 * * ?';

    /**
     * @description Lo llama Salesforce a la hora programada. Solo lanza el Batch.
     * @param sc Contexto del job programado (lo pasa Salesforce)
     */
    public void execute( SchedulableContext sc ) {
        Database.executeBatch( new QuoteExpirationBatch() );
    }
}
