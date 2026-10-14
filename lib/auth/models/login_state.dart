import 'server.dart';

sealed class LoginState {
  const LoginState();
}

class Authenticating extends LoginState {
  const Authenticating();
}

class RequireSignIn extends LoginState {
  const RequireSignIn();
}

class ServerUnavailable extends LoginState {
  const ServerUnavailable();
}

class UntrustedCertificate extends LoginState {
  const UntrustedCertificate();
}

class VersionNotSupported extends LoginState {
  final Server server;
  const VersionNotSupported({required this.server});
}

class ApiClientError extends LoginState {
  final String error;
  final String? errorType;
  final int? statusCode;

  const ApiClientError({required this.error, this.errorType, this.statusCode});
}

class Authenticated extends LoginState {
  final String userId;
  final String serverId;
  const Authenticated({required this.userId, required this.serverId});
}

/// Silo accepted the password, but it is a temporary one the account has to
/// replace before it can do anything else (step 3.6). The login stays open
/// for the change: finish it with `AuthRepository.changeRequiredSiloPassword`
/// or end it with `cancelRequiredSiloPasswordChange`.
class SiloPasswordChangeRequired extends LoginState {
  /// Fewest characters the new password may have.
  final int minimumLength;

  /// Most UTF-8 bytes the new password may have.
  final int maximumBytes;

  const SiloPasswordChangeRequired({
    required this.minimumLength,
    required this.maximumBytes,
  });
}

/// Silo refused the new password, or the change could not be sent. The login
/// is still open, so the person can try another one. [detail] is Silo's own
/// text for a refused password; null when the request itself failed.
class SiloPasswordChangeRejected extends LoginState {
  final String? detail;

  const SiloPasswordChangeRejected({this.detail});
}

/// The account has a temporary password, and Silo doesn't let it be changed
/// from here (password changes are switched off on the server). The login
/// has been ended; the person changes it in Silo's web app.
class SiloPasswordChangeUnavailable extends LoginState {
  const SiloPasswordChangeUnavailable();
}

/// The new password was saved, but the login could not be renewed to lift
/// the temporary restriction (no network, say). The login has been ended;
/// signing in with the new password works.
class SiloPasswordChangedSignInAgain extends LoginState {
  const SiloPasswordChangedSignInAgain();
}
