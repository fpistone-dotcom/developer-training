/**
 * @description DEV #3: the "alarm clock" of Part 2. Salesforce runs it every night at
 *              3:00 (after the DEV #1 job at 1:00 and the DEV #4 job at 2:00) and it
 *              only launches RenewalQuoteBatch, with no logic of its own.
 *
 *              To schedule it (only once, for example from Execute Anonymous):
 *              System.schedule( RenewalQuoteScheduler.JOB_NAME,
 *                               RenewalQuoteScheduler.CRON_EXPRESSION,
 *                               new RenewalQuoteScheduler() );
 */
public with sharing class RenewalQuoteScheduler implements Schedulable {

    public static final String JOB_NAME = 'Renewal Quote Generation - Nightly';

    // Seconds Minutes Hours Day-of-month Month Day-of-week: every day at 3:00
    public static final String CRON_EXPRESSION = '0 0 3 * * ?';

    // Chunks of 1 Contract: CPQ enqueues one Queueable per Renewal Quote, and from a Batch
    // only 1 can be enqueued per execute. Also, each Contract gets its own limits.
    public static final Integer BATCH_SIZE = 1;

    /**
     * @description Called by Salesforce at the scheduled time. It only launches the Batch.
     * @param sc Scheduled job context (passed by Salesforce)
     */
    public void execute( SchedulableContext sc ) {
        Database.executeBatch( new RenewalQuoteBatch(), BATCH_SIZE );
    }
}
