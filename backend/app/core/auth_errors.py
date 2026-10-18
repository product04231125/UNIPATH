from app.schemas.common import ErrorCode


class AuthError(Exception):
    def __init__(self, status: int, code: ErrorCode, message: str):
        self.status, self.code, self.message = status, code, message


def unauthenticated():
    return AuthError(
        401, ErrorCode.UNAUTHENTICATED, "로그인 정보를 확인하거나 다시 로그인해 주세요."
    )


def forbidden():
    return AuthError(403, ErrorCode.FORBIDDEN, "이 작업을 수행할 권한이 없습니다.")


def conflict():
    return AuthError(
        409, ErrorCode.CONFLICT, "이미 처리되었거나 다른 변경이 있습니다. 새로 조회해 주세요."
    )
