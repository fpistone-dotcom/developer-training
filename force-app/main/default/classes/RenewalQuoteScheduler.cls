/**
 * @description DEV #3: el "despertador" de la Parte 2. Salesforce lo ejecuta todas las noches a
 *              las 3:00 (después de los jobs del DEV #1 a la 1:00 y del DEV #4 a las 2:00) y
 *              solo lanza RenewalQuoteBatch, sin lógica propia.
 *
 *              Para programarlo (una sola vez, por ejemplo desde Execute Anonymous):
 *              System.schedule( RenewalQuoteScheduler.JOB_NAME,
 *                               RenewalQuoteScheduler.CRON_EXPRESSION,
 *                               new RenewalQuoteScheduler() );
 */
public with sharing class RenewalQuoteScheduler implements Schedulable {

    public static final String JOB_NAME = 'Renewal Quote Generation - Nightly';

    // Segundo Minuto Hora Día-del-mes Mes Día-de-la-semana: todos los días a las 3:00
    public static final String CRON_EXPRESSION = '0 0 3 * * ?';

    // Tandas de 1 Contract: CPQ encola un Queueable por cada Renewal Quote y desde un Batch
    // solo se puede encolar 1 por execute. Además, cada Contract tiene sus propios límites.
    public static final Integer BATCH_SIZE = 1;

    /**
     * @description Lo llama Salesforce a la hora programada. Solo lanza el Batch.
     * @param sc Contexto del job programado (lo pasa Salesforce)
     */
    public void execute( SchedulableContext sc ) {
        Database.executeBatch( new RenewalQuoteBatch(), BATCH_SIZE );
    }
}
