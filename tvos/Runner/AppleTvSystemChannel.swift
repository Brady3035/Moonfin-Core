import Flutter
import GameController
import UIKit

@MainActor
final class AppleTvSystemChannel: NSObject, UITextFieldDelegate {
    private let channel: FlutterMethodChannel
    private weak var gamepadHost: GCEventViewController?
    private let textField = UITextField(frame: .zero)
    private var textInputResult: FlutterResult?

    init(messenger: FlutterBinaryMessenger, gamepadHost: GCEventViewController) {
        channel = FlutterMethodChannel(
            name: "moonfin/appletv_system", binaryMessenger: messenger)
        self.gamepadHost = gamepadHost
        super.init()
        textField.delegate = self
        textField.returnKeyType = .done
        textField.enablesReturnKeyAutomatically = false
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setIdleTimerDisabled":
            let disabled = (call.arguments as? Bool) ?? false
            UIApplication.shared.isIdleTimerDisabled = disabled
            result(nil)
        case "setGamepadNavigationEnabled":
            gamepadHost?.controllerUserInteractionEnabled = (call.arguments as? Bool) ?? false
            result(nil)
        case "showTextInput":
            guard let arguments = call.arguments as? [String: Any] else {
                result(FlutterError(
                    code: "invalid_text_input",
                    message: "Missing tvOS text input arguments",
                    details: nil))
                return
            }
            // Without this the replaced request never completes, and the Dart
            // side waiting on it stops taking input for the session.
            finishTextInput(with: nil)

            textField.text = arguments["text"] as? String ?? ""
            textField.placeholder = arguments["hint"] as? String
            textField.isSecureTextEntry = arguments["obscureText"] as? Bool ?? false
            textField.keyboardType = keyboardType(for: arguments["purpose"] as? String)
            gamepadHost?.view.addSubview(textField)
            textInputResult = result
            if !textField.becomeFirstResponder() {
                textInputResult = nil
                textField.removeFromSuperview()
                result(FlutterError(
                    code: "text_input_unavailable",
                    message: "Unable to present tvOS text input",
                    details: nil))
            }
        case "hideTextInput":
            finishTextInput(with: nil)
            result(nil)
        case "exitApp":
            result(nil)
            exit(0)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func keyboardType(for purpose: String?) -> UIKeyboardType {
        switch purpose {
        case "url":
            return .URL
        case "email":
            return .emailAddress
        case "numeric":
            return .numberPad
        default:
            return .default
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        let completion = textInputResult
        textInputResult = nil
        textField.removeFromSuperview()
        completion?(textField.text ?? "")
    }

    /// Ends a request and takes the field back out of the view, so none of it
    /// is left behind between two keyboards.
    private func finishTextInput(with value: String?) {
        let completion = textInputResult
        textInputResult = nil
        textField.resignFirstResponder()
        textField.removeFromSuperview()
        completion?(value)
    }
}

/// Lets the Remote app on an iPhone type into the keyboards Flutter draws.
///
/// tvOS only offers the phone keyboard while a native text field is first
/// responder, so this keeps a hidden one active for as long as a drawn
/// keyboard is open and mirrors its text both ways. An empty input view takes
/// the place of the system keyboard, so the TV still shows only the drawn one.
@MainActor
final class AppleTvRemoteTextChannel: NSObject, UITextFieldDelegate {
    private let channel: FlutterMethodChannel
    private weak var flutterViewController: FlutterViewController?
    private let textField = RemoteTextField(frame: .zero)
    private var isActive = false

    init(messenger: FlutterBinaryMessenger, flutterViewController: FlutterViewController) {
        channel = FlutterMethodChannel(
            name: "moonfin/appletv_remote_text", binaryMessenger: messenger)
        self.flutterViewController = flutterViewController
        super.init()
        textField.delegate = self
        textField.returnKeyType = .done
        textField.enablesReturnKeyAutomatically = false
        textField.autocorrectionType = .no
        textField.inputView = UIView(frame: .zero)
        textField.pressTarget = flutterViewController
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "start":
            stop()
            guard let host = flutterViewController?.view else {
                result(false)
                return
            }
            textField.text = arguments["text"] as? String ?? ""
            textField.placeholder = arguments["hint"] as? String
            textField.isSecureTextEntry = arguments["obscureText"] as? Bool ?? false
            textField.keyboardType = keyboardType(for: arguments["purpose"] as? String)
            // Inside the Flutter view, so presses the field passes on still
            // travel the responder chain Flutter expects.
            host.addSubview(textField)
            isActive = true
            if !textField.becomeFirstResponder() {
                stop()
                result(false)
                return
            }
            result(true)
        case "update":
            let text = arguments["text"] as? String ?? ""
            if isActive && textField.text != text {
                textField.text = text
            }
            result(nil)
        case "stop":
            stop()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func keyboardType(for purpose: String?) -> UIKeyboardType {
        switch purpose {
        case "url":
            return .URL
        case "email":
            return .emailAddress
        case "numeric":
            return .numberPad
        default:
            return .default
        }
    }

    @objc private func textDidChange() {
        guard isActive else { return }
        channel.invokeMethod("changed", arguments: textField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard isActive else { return true }
        // Dart closes the drawn keyboard, and that stops this field.
        channel.invokeMethod("submitted", arguments: textField.text ?? "")
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        // Something else took first responder, such as the native keyboard.
        // The drawn keyboard stays up, it just loses the phone.
        guard isActive else { return }
        isActive = false
        textField.removeFromSuperview()
    }

    private func stop() {
        guard isActive else { return }
        isActive = false
        textField.resignFirstResponder()
        textField.removeFromSuperview()
    }
}

/// Hands every press to Flutter, so the Siri Remote keeps driving the drawn
/// keyboard while this field holds first responder.
private final class RemoteTextField: UITextField {
    weak var pressTarget: UIResponder?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressTarget?.pressesBegan(presses, with: event)
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressTarget?.pressesChanged(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressTarget?.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressTarget?.pressesCancelled(presses, with: event)
    }
}
