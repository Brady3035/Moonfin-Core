import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tvOS runner's hidden field that lets the iPhone Remote app type into
/// the drawn keyboards.
const _remoteTextChannel = MethodChannel('moonfin/appletv_remote_text');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> nativeCalls;

  setUp(() {
    nativeCalls = [];
    CustomTVTextField.debugOffersRemoteText = true;
  });

  tearDown(() => CustomTVTextField.debugOffersRemoteText = false);

  void recordChannel(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_remoteTextChannel, (call) async {
      nativeCalls.add(call);
      return call.method == 'start' ? true : null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_remoteTextChannel, null),
    );
  }

  Future<void> sendFromPhone(
    WidgetTester tester,
    String method,
    String text,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _remoteTextChannel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, text)),
      (_) {},
    );
    await tester.pump();
  }

  Iterable<String> methods() => nativeCalls.map((call) => call.method);

  Future<(CustomTVTextFieldState, TextEditingController, List<String>)>
  openField(WidgetTester tester) async {
    final key = GlobalKey<CustomTVTextFieldState>();
    final controller = TextEditingController(text: 'ab');
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomTVTextField(
            key: key,
            controller: controller,
            hint: 'Search',
            keyboardStyle: KeyboardStyle.docked,
            popParentOnKeyboardClose: false,
            onFieldSubmitted: submitted.add,
          ),
        ),
      ),
    );
    key.currentState!.openKeyboard();
    // The field blinks forever once it has focus, so settle is not available.
    await tester.pump(const Duration(milliseconds: 50));
    return (key.currentState!, controller, submitted);
  }

  testWidgets('opening a drawn keyboard starts the hidden field', (
    tester,
  ) async {
    recordChannel(tester);

    await openField(tester);

    expect(methods(), ['start']);
    expect(nativeCalls.single.arguments, {
      'text': 'ab',
      'hint': 'Search',
      'purpose': 'text',
      'obscureText': false,
    });
  });

  testWidgets('typing on the phone fills the field without echoing back', (
    tester,
  ) async {
    recordChannel(tester);
    final (_, controller, _) = await openField(tester);

    await sendFromPhone(tester, 'changed', 'abc');

    expect(controller.text, 'abc');
    expect(methods(), ['start']);
  });

  testWidgets('typing on the TV keyboard updates the phone', (tester) async {
    recordChannel(tester);
    final (_, controller, _) = await openField(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
    await tester.pump();

    expect(controller.text, 'abx');
    expect(methods(), ['start', 'update']);
    expect(nativeCalls.last.arguments, {'text': 'abx'});
  });

  testWidgets('Return on the phone submits and stops the hidden field', (
    tester,
  ) async {
    recordChannel(tester);
    final (_, controller, submitted) = await openField(tester);

    await sendFromPhone(tester, 'submitted', 'hello');
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.text, 'hello');
    expect(submitted, ['hello']);
    expect(methods(), ['start', 'stop']);
  });

  testWidgets('closing the keyboard stops the hidden field once', (
    tester,
  ) async {
    recordChannel(tester);
    final (field, _, _) = await openField(tester);

    field.closeKeyboard(submit: false);
    await tester.pump(const Duration(milliseconds: 50));
    await sendFromPhone(tester, 'changed', 'late');

    expect(methods(), ['start', 'stop']);
  });

  testWidgets('switching to the native keyboard stops the hidden field', (
    tester,
  ) async {
    recordChannel(tester);
    final (field, _, _) = await openField(tester);

    field.switchToSystemKeyboard();
    await tester.pump(const Duration(milliseconds: 50));

    expect(methods(), ['start', 'stop']);
  });

  testWidgets('a runner without the channel leaves the keyboard working', (
    tester,
  ) async {
    final (_, controller, _) = await openField(tester);

    expect(controller.text, 'ab');
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds off tvOS never call the channel', (tester) async {
    CustomTVTextField.debugOffersRemoteText = false;
    recordChannel(tester);

    final (field, _, _) = await openField(tester);
    field.closeKeyboard(submit: false);
    await tester.pump(const Duration(milliseconds: 50));

    expect(nativeCalls, isEmpty);
  });
}
