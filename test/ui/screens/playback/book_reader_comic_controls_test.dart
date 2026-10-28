import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/database/offline_database.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/playback/book_reader_screen.dart';
import 'package:moonfin/ui/widgets/reader/reader_chrome_bar.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _FakeClientFactory extends Fake implements MediaServerClientFactory {}

class _FakeItemsApi extends Fake implements ItemsApi {
  @override
  Future<Map<String, dynamic>> getItem(
    String itemId, {
    String? mediaSourceId,
    String? fields,
  }) async => {
    'Id': itemId,
    'Name': 'Comic',
    'Type': 'Book',
    'Path': '/books/c.cbz',
  };
}

class _FakeUserLibraryApi extends Fake implements UserLibraryApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// The comic is a downloaded file, so it opens without the network.
class _FakeOfflineRepository extends Fake implements OfflineRepository {
  final String path;

  _FakeOfflineRepository(this.path);

  @override
  Future<DownloadedItem?> getItem(String itemId) async => DownloadedItem(
    itemId: itemId,
    serverId: 'http://server',
    type: 'Book',
    name: 'Comic',
    localFilePath: path,
    metadataJson: '{}',
    downloadStatus: 2,
    downloadProgress: 1,
    fileSizeBytes: 0,
    playbackPositionTicks: 0,
    progressSynced: true,
    qualityPreset: 'original',
    downloadSource: 'manual',
  );
}

// A single opaque pixel, enough for a page.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = Directory.systemTemp.createTempSync('comic');
    final archive = Archive();
    for (var i = 1; i <= 3; i++) {
      archive.addFile(ArchiveFile('page$i.png', _png.length, _png));
    }
    final file = File('${dir.path}/c.cbz')
      ..writeAsBytesSync(ZipEncoder().encode(archive));

    final client = _MockClient();
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.itemsApi).thenReturn(_FakeItemsApi());
    when(() => client.userLibraryApi).thenReturn(_FakeUserLibraryApi());
    final getIt = GetIt.instance;
    getIt.registerSingleton<MediaServerClient>(client);
    getIt.registerSingleton<MediaServerClientFactory>(_FakeClientFactory());
    getIt.registerSingleton<OfflineRepository>(_FakeOfflineRepository(file.path));
  });

  tearDown(() async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    await GetIt.instance.reset();
    dir.deleteSync(recursive: true);
  });

  /// Opens the comic and waits for its pages, which load from disk.
  Future<void> openComic(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BookReaderScreen(itemId: 'comic-1'),
      ),
    );
    for (var i = 0; i < 50 && find.text('1/3').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('1/3'), findsOneWidget);
  }

  double barsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byType(ReaderTopBar),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;

  // The hide timer can start while the comic loads in real time, so both
  // clocks get past it.
  Future<void> waitForHide(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4500)),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The focused control's label, a pill's text or a button's tooltip.
  String? focusedControl() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? label;
    void findText(Element element) {
      final widget = element.widget;
      if (widget is Text) label ??= widget.data;
      if (label == null) element.visitChildElements(findText);
    }

    (context as Element).visitChildElements(findText);
    return label ?? context.findAncestorWidgetOfExactType<Tooltip>()?.message;
  }

  /// Lets a page turn's slide finish and the page label catch up.
  Future<void> settlePage(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('mouse', () {
    setUp(() => PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop));

    testWidgets('the bars fade on their own and come back when the mouse '
        'moves', (tester) async {
      await openComic(tester);
      expect(barsOpacity(tester), 1);

      await waitForHide(tester);
      expect(barsOpacity(tester), 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(640, 360));
      await mouse.moveTo(const Offset(650, 360));
      await tester.pump();
      expect(barsOpacity(tester), 1);
    });

    testWidgets('with fading off, a click in the middle still hides and '
        'shows the bars', (tester) async {
      await openComic(tester);
      // The page's double tap holds a single tap back until its timeout.
      await tester.tap(find.byTooltip('Controls hide automatically'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Controls stay visible'), findsOneWidget);

      await waitForHide(tester);
      expect(barsOpacity(tester), 1);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(600, 300));
      Future<void> click() async {
        await mouse.down(const Offset(640, 300));
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 300));
      }

      await click();
      expect(barsOpacity(tester), 0);

      // Moving the mouse leaves them hidden while fading is off.
      await mouse.moveTo(const Offset(620, 320));
      await tester.pump(const Duration(milliseconds: 300));
      expect(barsOpacity(tester), 0);

      await click();
      expect(barsOpacity(tester), 1);
    });
  });

  group('TV remote', () {
    setUp(() => PlatformDetection.setInterfaceLayout(InterfaceLayout.tv));

    testWidgets('while the bars are hidden the D-pad turns pages, and volume '
        'keys are left for the system', (tester) async {
      await openComic(tester);
      await waitForHide(tester);
      expect(barsOpacity(tester), 0);

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight), isTrue);
      await settlePage(tester);
      expect(find.text('2/3'), findsOneWidget);

      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp),
        isFalse,
      );
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeMute),
        isFalse,
      );
      await tester.pump();
      expect(barsOpacity(tester), 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(barsOpacity(tester), 1);
      expect(focusedControl(), 'Single');
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown),
        isFalse,
      );

      // With the bars up the D-pad moves through them instead.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settlePage(tester);
      expect(focusedControl(), 'Two-page');
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('the remote walks the controls bar in order, and its eye '
        'button turns the fading off', (tester) async {
      await openComic(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedControl(), 'Single');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedControl(), 'Single');
      final walked = <String?>[];
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        walked.add(focusedControl());
      }
      expect(walked.toSet().toList(), [
        'Two-page',
        'Vertical',
        'Left to right',
        'Thumbnails',
        'Invert colors',
        'Controls hide automatically',
      ]);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.byTooltip('Controls stay visible'), findsOneWidget);

      await waitForHide(tester);
      expect(barsOpacity(tester), 1);
    });
  });
}
