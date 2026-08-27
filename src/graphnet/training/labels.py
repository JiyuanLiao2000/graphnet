"""Class(es) for constructing training labels at runtime."""

from abc import ABC, abstractmethod
import torch
from torch_geometric.data import Data
from graphnet.utilities.logging import Logger


class Label(ABC, Logger):
    """Base `Label` class for producing labels from single `Data` instance."""

    def __init__(self, key: str):
        """Construct `Label`.

        Args:
            key: The name of the field in `Data` where the label will be
                stored. That is, `graph[key] = label`.
        """
        self._key = key

        # Base class constructor
        super().__init__(name=__name__, class_name=self.__class__.__name__)

    @property
    def key(self) -> str:
        """Return value of `key`."""
        return self._key

    @abstractmethod
    def __call__(self, graph: Data) -> torch.tensor:
        """Label-specific implementation."""


class Direction(Label):
    """Class for producing particle direction/pointing label."""

    def __init__(
        self,
        key: str = "direction",
        azimuth_key: str = "azimuth",
        zenith_key: str = "zenith",
    ):
        """Construct `Direction`.

        Args:
            key: The name of the field in `Data` where the label will be
                stored. That is, `graph[key] = label`.
            azimuth_key: The name of the pre-existing key in `graph` that will
                be used to access the azimiuth angle, used when calculating
                the direction.
            zenith_key: The name of the pre-existing key in `graph` that will
                be used to access the zenith angle, used when calculating the
                direction.
        """
        self._azimuth_key = azimuth_key
        self._zenith_key = zenith_key

        # Base class constructor
        super().__init__(key=key)

    def __call__(self, graph: Data) -> torch.tensor:
        """Compute label for `graph`."""
        x = torch.cos(graph[self._azimuth_key]) * torch.sin(
            graph[self._zenith_key]
        ).reshape(-1, 1)
        y = torch.sin(graph[self._azimuth_key]) * torch.sin(
            graph[self._zenith_key]
        ).reshape(-1, 1)
        z = torch.cos(graph[self._zenith_key]).reshape(-1, 1)
        return torch.cat((x, y, z), dim=1)


class JointLabel(Label):
    """Generate joint labels for position and direction."""

    def __init__(
        self,
        position_keys: tuple = ("position_x", "position_y", "position_z"),
        direction_key: str = "direction",
        azimuth_key: str = "azimuth",
        zenith_key: str = "zenith",
        key: str = "joint_labels",  # The name of the output field in Data
    ):
        """Initialize JointLabel.

        Args:
            position_keys: Tuple of keys for the position labels.
            direction_key: Key for the precomputed direction label.
            azimuth_key: Key for azimuth angle in Data.
            zenith_key: Key for zenith angle in Data.
            key: The name of the combined joint labels field in Data.
        """
        self._position_keys = position_keys
        self._direction_key = direction_key
        self._azimuth_key = azimuth_key
        self._zenith_key = zenith_key

        # Call parent class constructor
        super().__init__(key=key)

    def __call__(self, graph: Data) -> torch.tensor:
        """Compute joint labels for position and direction.

        Args:
            graph: The input Data object.

        Returns:
            A tensor containing joint labels (position and direction).
        """
        # Extract position labels
        position_labels = torch.stack(
            [graph[key] for key in self._position_keys], dim=1
        )

        # Compute direction labels
        x = torch.cos(graph[self._azimuth_key]) * torch.sin(graph[self._zenith_key])
        y = torch.sin(graph[self._azimuth_key]) * torch.sin(graph[self._zenith_key])
        z = torch.cos(graph[self._zenith_key])
        direction_labels = torch.cat([x.unsqueeze(1), y.unsqueeze(1), z.unsqueeze(1)], dim=1)

        # Combine position and direction labels
        joint_labels = torch.cat([position_labels, direction_labels], dim=1)

        # Store the result in the Data object
        graph[self.key] = joint_labels

        return joint_labels

class Track(Label):
    """Class for producing NuMuCC label.

    Label is set to `1` if the event is a NuMu CC event, else `0`.
    """

    def __init__(
        self,
        key: str = "track",
        pid_key: str = "pid",
        interaction_key: str = "interaction_type",
    ):
        """Construct `Track` label.

        Args:
            key: The name of the field in `Data` where the label will be
                stored. That is, `graph[key] = label`.
            pid_key: The name of the pre-existing key in `graph` that will
                be used to access the pdg encoding, used when calculating
                the direction.
            interaction_key: The name of the pre-existing key in `graph` that
                will be used to access the interaction type (1 denoting CC),
                used when calculating the direction.
        """
        self._pid_key = pid_key
        self._int_key = interaction_key

        # Base class constructor
        super().__init__(key=key)

    def __call__(self, graph: Data) -> torch.tensor:
        """Compute label for `graph`."""
        is_numu = torch.abs(graph[self._pid_key]) == 14
        is_cc = graph[self._int_key] == 1
        return (is_numu & is_cc).type(torch.int)
