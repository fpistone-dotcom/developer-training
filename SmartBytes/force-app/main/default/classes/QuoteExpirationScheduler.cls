/**
 * @description Part B of DEV #1: the "alarm clock" of the nightly process. Salesforce runs it
 *              every night and it only launches QuoteExpirationBatch, with no logic of its own
 *              (the logic lives in the Batch).
 *
 *              To schedule it (only once, for example from Execute Anonymous):
 *              System.schedule( QuoteExpirationScheduler.JOB_NAME,
 *                               QuoteExpirationScheduler.CRON_EXPRESSION,
 *                               new QuoteExpirationScheduler() );
 *              The job runs as the user who schedules it (it must be an admin, because it
 *              recalls approvals submitted by other users).
 */
public with sharing class QuoteExpirationScheduler implements Schedulable {

    public static final String JOB_NAME = 'Quote Expiration Recall - Nightly';

    // Seconds Minutes Hours Day-of-month Month Day-of-week: every day at 1:00
    public static final String CRON_EXPRESSION = '0 0 1 * * ?';

    /**
     * @description Called by Salesforce at the scheduled time. It only launches the Batch.
     * @param sc Scheduled job context (passed by Salesforce)
     */
    public void execute( SchedulableContext sc ) {
        Database.executeBatch( new QuoteExpirationBatch() );
    }
}
