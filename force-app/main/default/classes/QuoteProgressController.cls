/**
 * @description Controller of the quoteProgress LWC (DEV #5). Calculates the 5 steps of the
 *              quoting process for ONE Quote and returns them in order, each one with its status
 *              (done or not). The LWC only draws them: all the business rules live here,
 *              in Apex, so they can be tested and changed in a single place.
 *
 *              Efficiency: only 1 SOQL and 0 DML per call. Each call from the LWC is a
 *              new transaction with its own governor limits.
 *
 * Requirement DEV #5 (verbatim): "As a Sales User, I would like to be able to see a User-friendly
 * UI on the Quote record that shows my current progress in the Quoting process. Specifically, I
 * would like the following tasks to either have a green checkmark or red 'X': Quote Lines Added,
 * Quote Approved, Quote Document Created, Opportunity Closed Won, Quote Ordered."
 * Requirement parts and where they are covered:
 *   (A) "Quote Lines Added"        -> SBQQ__LineItemCount__c > 0 (CPQ Roll-Up Summary)
 *   (B) "Quote Approved"           -> SBQQ__Status__c in APPROVED_STATUS_SET
 *   (C) "Quote Document Created"   -> at least one SBQQ__QuoteDocument__c exists for this Quote
 *   (D) "Opportunity Closed Won"   -> SBQQ__Opportunity2__r.IsWon = true
 *   (E) "Quote Ordered"            -> SBQQ__Ordered__c = true
 *   (F) "green checkmark or red X" -> isDone of each step; the LWC picks the icon
 */
public with sharing class QuoteProgressController {

    // Text of each step, exactly as in the requirement. Public so the tests can use them.
    public static final String STEP_QUOTE_LINES = 'Quote Lines Added';
    public static final String STEP_APPROVED = 'Quote Approved';
    public static final String STEP_DOCUMENT = 'Quote Document Created';
    public static final String STEP_CLOSED_WON = 'Opportunity Closed Won';
    public static final String STEP_ORDERED = 'Quote Ordered';

    // Req (B): Presented and Accepted are statuses AFTER the approval in the CPQ lifecycle.
    // If an approved Quote moves to Presented, the step has to stay green (assumption
    // confirmed by Francisco). Set and not List: we only ask "is it in there?" (contains).
    public static final Set<String> APPROVED_STATUS_SET = new Set<String>{ 'Approved', 'Presented', 'Accepted' };

    public static final String QUOTE_NOT_FOUND_MESSAGE = 'The Quote was not found or you do not have access to it.';

    /**
     * @description One step of the progress bar. Minimal 2-field class: it is the way to
     *              send structured data to the browser. @AuraEnabled on each field makes
     *              it travel in the JSON the LWC receives.
     */
    public class ProgressStep {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isDone;

        public ProgressStep( String label, Boolean isDone ) {
            this.label = label;
            this.isDone = isDone;
        }
    }

    /**
     * @description Returns the 5 steps of the Quote, in the order of the requirement.
     *              @AuraEnabled: allows calling it from the LWC. Without cacheable=true on purpose:
     *              that way each call (when the page opens or with the Refresh button) gets fresh data.
     * @param quoteId Id of the Quote being viewed (the page recordId)
     * @return Ordered list of 5 ProgressStep
     */
    @AuraEnabled
    public static List<ProgressStep> getProgressSteps( Id quoteId ) {
        // A single query: the Quote fields, the parent's IsWon (lookup) and the child
        // documents (subquery). SBQQ__R00N70000001lX7YEAU__r is the name of the relationship
        // SBQQ__QuoteDocument__c -> SBQQ__Quote__c: CPQ is an old package and never gave it a
        // readable name (verified with sf sobject describe). LIMIT 1 because we only care whether
        // at least one exists, not how many.
        List<SBQQ__Quote__c> quoteList = [
            SELECT Id, SBQQ__LineItemCount__c, SBQQ__Status__c, SBQQ__Ordered__c,
                SBQQ__Opportunity2__c, SBQQ__Opportunity2__r.IsWon,
                ( SELECT Id FROM SBQQ__R00N70000001lX7YEAU__r LIMIT 1 )
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
        ];

        // The Quote does not exist (deleted) or the user cannot see it (with sharing): readable error.
        if ( quoteList.isEmpty() ) {
            AuraHandledException notFoundException = new AuraHandledException( QUOTE_NOT_FOUND_MESSAGE );
            // setMessage: without it, getMessage() returns "Script-thrown exception" and the test
            // cannot check the text. The browser receives the constructor message anyway.
            notFoundException.setMessage( QUOTE_NOT_FOUND_MESSAGE );
            throw notFoundException;
        }

        return buildSteps( quoteList[0] );
    }

    /**
     * @description Evaluates each step separately. The steps are NOT sequential: for example,
     *              an Amendment is Ordered without being approved or Closed Won (seen in the org).
     * @param quote Quote with the queried fields
     * @return Ordered list of 5 ProgressStep
     */
    private static List<ProgressStep> buildSteps( SBQQ__Quote__c quote ) {
        // Req (A): a Roll-Up Summary is never null (it is 0 with no lines)
        Boolean hasQuoteLines = quote.SBQQ__LineItemCount__c > 0;

        // Req (B)
        Boolean isApproved = APPROVED_STATUS_SET.contains( quote.SBQQ__Status__c );

        // Req (C): a subquery result is never null (with no children it is an empty list)
        Boolean hasDocument = !quote.SBQQ__R00N70000001lX7YEAU__r.isEmpty();

        // Req (D): the lookup is checked first. Without an Opportunity, SBQQ__Opportunity2__r is
        // null and reading its IsWon would throw a NullPointerException.
        Boolean isClosedWon = false;
        if ( quote.SBQQ__Opportunity2__c != null ) {
            isClosedWon = quote.SBQQ__Opportunity2__r.IsWon;
        }

        // Req (E)
        Boolean isOrdered = quote.SBQQ__Ordered__c;

        List<ProgressStep> stepList = new List<ProgressStep>();
        stepList.add( new ProgressStep( STEP_QUOTE_LINES, hasQuoteLines ) );
        stepList.add( new ProgressStep( STEP_APPROVED, isApproved ) );
        stepList.add( new ProgressStep( STEP_DOCUMENT, hasDocument ) );
        stepList.add( new ProgressStep( STEP_CLOSED_WON, isClosedWon ) );
        stepList.add( new ProgressStep( STEP_ORDERED, isOrdered ) );
        return stepList;
    }
}
