import { LightningElement, api } from 'lwc';
// Importa el método @AuraEnabled de Apex como si fuera una función de JavaScript
import getProgressSteps from '@salesforce/apex/QuoteProgressController.getProgressSteps';

/**
 * DEV #5: muestra los 5 pasos del proceso de cotización de la Quote con un check verde o una
 * X roja. No decide nada: dibuja lo que devuelve QuoteProgressController.getProgressSteps.
 */
export default class QuoteProgress extends LightningElement {
    // Salesforce completa recordId solo con el Id de la Quote que se está mirando
    @api recordId;

    steps = [];          // pasos listos para dibujar
    isLoading = false;   // muestra el spinner mientras espera a Apex
    errorMessage;        // texto del error, si Apex falla

    // Se ejecuta cuando el componente aparece en la página: carga los datos al abrir la Quote
    connectedCallback() {
        this.loadSteps();
    }

    // Botón Refresh: vuelve a pedir los datos (por ejemplo, después de aprobar la Quote o de
    // generar un documento en otra pantalla)
    handleRefresh() {
        this.loadSteps();
    }

    // Llamada imperativa a Apex: devuelve una Promise (then = salió bien, catch = error)
    loadSteps() {
        this.isLoading = true;
        this.errorMessage = undefined;

        getProgressSteps({ quoteId: this.recordId })
            .then((result) => {
                // A cada paso le agregamos el ícono, el color y el texto alternativo que usa el HTML
                this.steps = result.map((step) => ({
                    label: step.label,
                    isDone: step.isDone,
                    iconName: step.isDone ? 'utility:success' : 'utility:close',
                    iconVariant: step.isDone ? 'success' : 'error',
                    iconText: step.isDone ? 'Completed' : 'Not completed'
                }));
            })
            .catch((error) => {
                // El mensaje de la AuraHandledException llega en error.body.message
                this.steps = [];
                this.errorMessage = error && error.body && error.body.message
                    ? error.body.message
                    : 'Unable to load the Quote progress.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Texto "3 of 5" del encabezado
    get progressSummary() {
        const doneCount = this.steps.filter((step) => step.isDone).length;
        return doneCount + ' of ' + this.steps.length;
    }

    get hasSteps() {
        return this.steps.length > 0;
    }
}
