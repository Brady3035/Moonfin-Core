import '../../util/silo_failure_message.dart';
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

class ClientCertificateRequired extends LoginState {
  const ClientCertificateRequired();
}

class VersionNotSupported extends LoginState {
  final Server server;
  const VersionNotSupported({required this.server});
}

/// The server refused the sign in with a 403: the account can't be used right
/// now. Jellyfin doesn't say why outside development, and it can be the user's
/// access schedule, a disabled account or a lockout.
class SignInForbidden extends LoginState {
  const SignInForbidden();
}

class ApiClientError extends LoginState {
  final String error;
  final String? errorType;
  final int? statusCode;

  const ApiClientError({required this.error, this.errorType, this.statusCode});
}

/// Silo refused the sign-in for a reason a person can act on (17.3): wait
/// and try again, or update Moonfin or Silo. [failure] has the text.
class SiloRequestRefused extends LoginState {
  final SiloFailure failure;
  const SiloRequestRefused(this.failure);
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

/// A sign-in with a code (14.1) was approved for an account holding a
/// temporary password. Replacing it needs the password in use, which a code
/// sign-in doesn't have, so the login has been ended: sign in with the
/// password once to replace it.
class SiloCodeSignInPasswordChangeRequired extends LoginState {
  const SiloCodeSignInPasswordChangeRequired();
}

/// The new password was saved, but the login could not be renewed to lift
/// the temporary restriction (no network, say). The login has been ended;
/// signing in with the new password works.
class SiloPasswordChangedSignInAgain extends LoginState {
  const SiloPasswordChangedSignInAgain();
}

/// The Silo password was accepted, but the account's main profile, the one
/// Moonfin signs in as (decision D9), is locked with a PIN. PIN entry comes
/// with the optional profiles phase (step 18.4); until then the login is
/// ended and the screen explains why (step 3.7).
class SiloMainProfileLocked extends LoginState {
  /// The main profile's name, as Silo shows it.
  final String profileName;

  const SiloMainProfileLocked({required this.profileName});
}
