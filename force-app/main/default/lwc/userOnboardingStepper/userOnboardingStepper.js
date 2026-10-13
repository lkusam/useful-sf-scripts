import { LightningElement, api } from 'lwc';

/**
 * Animated step indicator. Completed steps are clickable (the parent decides
 * what to do with the `stepselect` event); the current and future steps are not.
 */
export default class UserOnboardingStepper extends LightningElement {
    /** Array of { value: Number (1-based), label: String } */
    @api steps = [];
    /** 1-based index of the active step */
    @api currentStep = 1;

    get items() {
        const total = this.steps.length;
        return this.steps.map((step, index) => {
            const isDone = step.value < this.currentStep;
            const isCurrent = step.value === this.currentStep;
            let state = 'upcoming';
            let stateLabel = 'not started';
            if (isDone) {
                state = 'done';
                stateLabel = 'completed, go back to edit';
            } else if (isCurrent) {
                state = 'current';
                stateLabel = 'current step';
            }
            return {
                value: step.value,
                label: step.label,
                isDone,
                isLocked: !isDone,
                hasLine: index < total - 1,
                ariaCurrent: isCurrent ? 'step' : null,
                ariaLabel: `Step ${step.value} of ${total}: ${step.label}, ${stateLabel}`,
                itemClass: `step is-${state}`
            };
        });
    }

    handleClick(event) {
        const value = Number(event.currentTarget.dataset.step);
        if (value < this.currentStep) {
            this.dispatchEvent(new CustomEvent('stepselect', { detail: value }));
        }
    }
}
