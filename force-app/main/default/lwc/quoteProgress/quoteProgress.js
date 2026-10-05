import { LightningElement, api } from 'lwc';
// Imports the @AuraEnabled Apex method as if it were a JavaScript function
import getProgressSteps from '@salesforce/apex/QuoteProgressController.getProgressSteps';

/**
 * DEV #5: shows the 5 steps of the Quote's quoting process with a green check or a
 * red X. It decides nothing: it draws what QuoteProgressController.getProgressSteps returns.
 */
export default class QuoteProgress extends LightningElement {
    // Salesforce fills recordId automatically with the Id of the Quote being viewed
    @api recordId;

    steps = [];          // steps ready to draw
    isLoading = false;   // shows the spinner while waiting for Apex
    errorMessage;        // error text, if Apex fails

    // Runs when the component is added to the page: loads the data when the Quote opens
    connectedCallback() {
        this.loadSteps();
    }

    // Refresh button: asks for the data again (for example, after approving the Quote or
    // generating a document on another screen)
    handleRefresh() {
        this.loadSteps();
    }

    // Imperative Apex call: returns a Promise (then = success, catch = error)
    loadSteps() {
        this.isLoading = true;
        this.errorMessage = undefined;

        getProgressSteps({ quoteId: this.recordId })
            .then((result) => {
                // We add to each step the icon, color and alternative text the HTML uses
                this.steps = result.map((step) => ({
                    label: step.label,
                    isDone: step.isDone,
                    iconName: step.isDone ? 'utility:success' : 'utility:close',
                    iconVariant: step.isDone ? 'success' : 'error',
                    iconText: step.isDone ? 'Completed' : 'Not completed'
                }));
            })
            .catch((error) => {
                // The AuraHandledException message arrives in error.body.message
                this.steps = [];
                this.errorMessage = error && error.body && error.body.message
                    ? error.body.message
                    : 'Unable to load the Quote progress.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // "3 of 5" text in the header
    get progressSummary() {
        const doneCount = this.steps.filter((step) => step.isDone).length;
        return doneCount + ' of ' + this.steps.length;
    }

    get hasSteps() {
        return this.steps.length > 0;
    }
}
