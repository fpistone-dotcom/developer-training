/**
 * @description DEV #4: the "alarm clock" of the nightly recount. Salesforce runs it every
 *              night at 2:00 (one hour after the DEV #1 job, so they do not overlap) and it only
 *              launches ActiveSubscriptionRecountBatch, with no logic of its own.
 *
 *              To schedule it (only once, for example from Execute Anonymous):
 *              System.schedule( ActiveSubscriptionRecountScheduler.JOB_NAME,
 *                               ActiveSubscriptionRecountScheduler.CRON_EXPRESSION,
 *                               new ActiveSubscriptionRecountScheduler() );
 */
public with sharing class ActiveSubscriptionRecountScheduler implements Schedulable {

    public static final String JOB_NAME = 'Active Subscriptions Recount - Nightly';

    // Seconds Minutes Hours Day-of-month Month Day-of-week: every day at 2:00
    public static final String CRON_EXPRESSION = '0 0 2 * * ?';

    /**
     * @description Called by Salesforce at the scheduled time. It only launches the Batch.
     * @param sc Scheduled job context (passed by Salesforce)
     */
    public void execute( SchedulableContext sc ) {
        Database.executeBatch( new ActiveSubscriptionRecountBatch() );
    }
}
