// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_app/main.dart';
import 'package:camera/camera.dart';

void main() {
  testWidgets('Navigation smoke test', (WidgetTester tester) async {
    // Initialize the camera
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    // Build the app and trigger a frame.
    await tester.pumpWidget(SignLanguageApp(camera: firstCamera));

    // Verify Home Page is displayed by checking the presence of "Capture & Translate" button
    expect(find.text('Capture & Translate'), findsOneWidget);

    // Tap on the second navigation item (Uploads)
    await tester.tap(find.text('Uploads'));
    await tester.pumpAndSettle();

    // Verify Upload Page is displayed by checking the presence of "Upload" button
    expect(find.text('Upload'), findsOneWidget);

    // Tap on the third navigation item (Sign-Lang)
    await tester.tap(find.text('Sign-Lang'));
    await tester.pumpAndSettle();

    // Verify HandSignPage is displayed by checking the presence of 'Choose a Hand Sign:'
    expect(find.text('Choose a Hand Sign:'), findsOneWidget);
  });
}
