"""Maps each macro pad button to a semantic action."""

from enum import Enum


class PadAction(Enum):
    """Represents the four macro pad buttons and their associated actions."""

    APPROVE = "approve"
    REJECT = "reject"
    ACTION3 = "action3"
    ACTION4 = "action4"

    @property
    def key_code(self):
        """X11 keysym sent by the RP2040 for each button."""
        return {
            PadAction.APPROVE: 0xFFCA,  # XK_F13
            PadAction.REJECT:  0xFFCB,  # XK_F14
            PadAction.ACTION3: 0xFFCC,  # XK_F15
            PadAction.ACTION4: 0xFFCD,  # XK_F16
        }[self]

    @property
    def f_key_number(self):
        """The F-key number associated with this action."""
        return {
            PadAction.APPROVE: 13,
            PadAction.REJECT:  14,
            PadAction.ACTION3: 15,
            PadAction.ACTION4: 16,
        }[self]

    @property
    def display_name(self):
        """Human-readable name for the action."""
        return {
            PadAction.APPROVE: "Approve / Yes",
            PadAction.REJECT:  "Reject / No",
            PadAction.ACTION3: "Action 3",
            PadAction.ACTION4: "Action 4",
        }[self]

    @property
    def default_search_terms(self):
        """Built-in default search terms for each action."""
        return {
            PadAction.APPROVE: [
                "Allow", "allow once", "allow for this chat",
                "Yes", "Approve", "Accept", "Confirm", "Continue",
                "Run", "Execute", "allow", "yes", "approve",
                "Allow Once", "Allow for This Chat",
            ],
            PadAction.REJECT: [
                "Deny", "deny", "No", "Reject", "Cancel", "Decline",
                "Don't Allow", "Block", "Stop", "no", "reject", "cancel",
            ],
            PadAction.ACTION3: [
                "Continue", "Next", "Skip", "Retry",
            ],
            PadAction.ACTION4: [
                "Stop", "Cancel", "Close", "Dismiss",
            ],
        }[self]

    @property
    def search_terms(self):
        """Active search terms -- uses custom config if set, otherwise defaults."""
        from services.button_config_store import ButtonConfigStore
        return ButtonConfigStore.shared().search_terms(self)
