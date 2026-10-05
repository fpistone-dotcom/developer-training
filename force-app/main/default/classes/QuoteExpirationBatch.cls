/**
 * @description Part B of DEV #1: every night (launched by QuoteExpirationScheduler) it finds
 *              the Quotes with a PENDING approval that have already expired and whose Opportunity
 *              is not won, and recalls them.
 *
 *              "Recall" (defined with the mentor): withdraw the pending approval, exactly like the
 *              "Recall" button in the UI. In Apex it is an Approval.ProcessWorkitemRequest with the
 *              'Removed' action. Salesforce runs the Approval Process Recall Action by itself
 *              (Set_Quote_Status_Draft) and unlocks the Quote: Approval.unlock is not needed.
 *              Assumption: Quotes that are already approved are not touched.
 *
 *              Why Batch: it processes the Quotes in chunks of 200 and each chunk has its own
 *              governor limits, so it works with any volume.
 *
 * Requirement DEV #1 (verbatim, second part): "If a Quote reaches the Quote Expiration Date
 * and the related Opportunity is still not 'Closed Won,' then the Quote approvals should be
 * recalled."
 * Requirement parts and where they are covered:
 *   (C) "reaches the Quote Expiration Date"       -> start: SBQQ__ExpirationDate__c <= TODAY
 *   (D) "the related Opportunity is still not     -> start: with Opportunity and IsWon = false
 *        'Closed Won'"
 *   (E) "the Quote approvals should be recalled"  -> recallPendingApprovals ('Removed' action)
 */
public with sharing class QuoteExpirationBatch implements Database.Batchable<SObject> {

    // Status set by the Approval Processes while the approval is pending
    public static final String STATUS_IN_REVIEW = 'In Review';

    // Req (E): 'Removed' is the action of the "Recall" button on a pending approval
    public static final String RECALL_ACTION = 'Removed';

    private static final String RECALL_COMMENT = 'Recalled automatically: the Quote reached its Expiration Date and the Opportunity is not Closed Won.';
    private static final String CLASS_NAME = 'QuoteExpirationBatch';

    /**
     * @description Req (C) and (D). Gets the Quotes pending approval, expired, with an
     *              Opportunity, and with that Opportunity not won. Quotes without an Opportunity
     *              are left out (documented assumption).
     * @param bc Batch context (passed by Salesforce)
     * @return QueryLocator with the Quotes to process
     */
    public Database.QueryLocator start( Database.BatchableContext bc ) {
        return Database.getQueryLocator( [
            SELECT Id
            FROM SBQQ__Quote__c
            WHERE SBQQ__Status__c = :STATUS_IN_REVIEW
            AND SBQQ__ExpirationDate__c <= TODAY
            AND SBQQ__Opportunity2__c != null
            AND SBQQ__Opportunity2__r.IsWon = false
        ] );
    }

    /**
     * @description Runs once for each chunk of (up to) 200 Quotes. It only delegates.
     * @param bc        Batch context
     * @param quoteList Quotes in this chunk
     */
    public void execute( Database.BatchableContext bc, List<SBQQ__Quote__c> quoteList ) {
        recallPendingApprovals( quoteList );
    }

    /**
     * @description Nothing to do at the end: the errors were already saved in each chunk.
     * @param bc Batch context
     */
    public void finish( Database.BatchableContext bc ) {
        // Empty on purpose: the Database.Batchable interface requires this method
    }

    /**
     * @description Req (E). Recalls the pending approvals of these Quotes.
     *              A single work item query and a single Approval.process for the whole chunk.
     *              With allOrNone = false, if one recall fails the others still go through, and
     *              the error is stored in Error_Log__c.
     * @param quoteList Expired Quotes in this chunk
     */
    private static void recallPendingApprovals( List<SBQQ__Quote__c> quoteList ) {
        Set<Id> quoteIdSet = new Set<Id>();
        for ( SBQQ__Quote__c quote : quoteList ) {
            quoteIdSet.add( quote.Id );
        }

        // One work item = one approval waiting for an answer. They only exist while it is pending.
        List<Approval.ProcessWorkitemRequest> recallRequestList = new List<Approval.ProcessWorkitemRequest>();
        // Parallel list: at position i, the Quote of request i (for the error log)
        List<Id> recalledQuoteIdList = new List<Id>();
        for ( ProcessInstanceWorkitem workitem : [
            SELECT Id, ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId IN :quoteIdSet
        ] ) {
            Approval.ProcessWorkitemRequest recallRequest = new Approval.ProcessWorkitemRequest();
            recallRequest.setWorkitemId( workitem.Id );
            recallRequest.setAction( RECALL_ACTION );
            recallRequest.setComments( RECALL_COMMENT );
            recallRequestList.add( recallRequest );
            recalledQuoteIdList.add( workitem.ProcessInstance.TargetObjectId );
        }

        // A Quote can be "In Review" without a pending approval (for example, if someone
        // changed the Status manually). In that case there is nothing to recall.
        if ( recallRequestList.isEmpty() ) {
            return;
        }

        List<Approval.ProcessResult> resultList = Approval.process( recallRequestList, false );

        // The results come back in the same order as the requests: they are read by position
        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        for ( Integer i = 0; i < resultList.size(); i++ ) {
            if ( !resultList[i].isSuccess() ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, recalledQuoteIdList[i],
                    'Recall failed: ' + resultList[i].getErrors()[0].getMessage() ) );
            }
        }
        ErrorLogUtil.saveLogs( errorLogList );
    }
}
