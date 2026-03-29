"""Defines whether a button uses a simple preset action or complex search terms."""


class ButtonMode:
    """Represents either a simple preset action or complex search-term mode."""

    def __init__(self, mode_type, simple_action=None):
        """Create a ButtonMode.

        Args:
            mode_type: "simple" or "complex"
            simple_action: SimpleAction instance (required if mode_type is "simple")
        """
        self.mode_type = mode_type
        self.simple_action = simple_action

    @property
    def is_simple(self):
        return self.mode_type == "simple"

    @property
    def display_label(self):
        if self.is_simple and self.simple_action is not None:
            return self.simple_action.display_name
        return "Search Terms"

    def to_dict(self):
        """Serialize to a JSON-compatible dict."""
        d = {"mode_type": self.mode_type}
        if self.simple_action is not None:
            d["simple_action"] = self.simple_action.value
        return d

    @classmethod
    def from_dict(cls, data):
        """Deserialize from a dict."""
        from models.simple_action import SimpleAction
        mode_type = data.get("mode_type", "complex")
        simple_action = None
        if "simple_action" in data and data["simple_action"]:
            try:
                simple_action = SimpleAction(data["simple_action"])
            except ValueError:
                pass
        return cls(mode_type, simple_action)

    @classmethod
    def complex(cls):
        return cls("complex")

    @classmethod
    def simple(cls, action):
        return cls("simple", action)

    def __eq__(self, other):
        if not isinstance(other, ButtonMode):
            return False
        return self.mode_type == other.mode_type and self.simple_action == other.simple_action
