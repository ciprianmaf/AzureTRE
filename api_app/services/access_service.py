from abc import abstractmethod
from typing import List

from fastapi.security import OAuth2AuthorizationCodeBearer
from models.domain.workspace import Workspace, WorkspaceRole
from models.domain.authentication import User, RoleAssignment


class AuthConfigValidationError(Exception):
    """Raised when the input auth information is invalid"""


class AccessService(OAuth2AuthorizationCodeBearer):
    @abstractmethod
    def extract_workspace_auth_information(self, data: dict) -> dict:
        pass

    @abstractmethod
    def get_user_role_assignments(self, user_id: str) -> dict:
        pass

    @staticmethod
    @abstractmethod
    def get_workspace_role(user: User, workspace: Workspace, user_role_assignments: List[RoleAssignment]) -> WorkspaceRole:
        pass
