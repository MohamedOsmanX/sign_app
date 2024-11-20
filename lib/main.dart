// lib/main.dart

import 'dart:async'; // For Timer
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(SignLanguageApp(camera: firstCamera));
}

class SignLanguageApp extends StatelessWidget {
  final CameraDescription camera;

  const SignLanguageApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sign Language Recognition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MainScreen(camera: camera),
    );
  }
}

// Function to get the backend URL based on platform
String getBackendUrl() {
  if (Platform.isAndroid) {
    return 'http://192.168.0.131:5000/predict'; // Android Emulator
  } else if (Platform.isIOS) {
    return 'http://localhost:5000/predict'; // iOS Simulator
  } else {
    // For Physical Devices, replace with your computer's local IP address
    return 'http://192.168.0.131:5000/predict'; // Example IP - Replace with your actual IP
  }
}

// الصفحة الرئيسية مع التنقل بين الصفحات
class MainScreen extends StatefulWidget {
  final CameraDescription camera;

  const MainScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(camera: widget.camera),
      UploadPage(),
      HandSignPage(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Color.fromARGB(
            255, 35, 146, 236), // Change color for Bottom Navigation
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Color.fromARGB(255, 5, 5, 5),
        unselectedItemColor: Color.fromARGB(255, 5, 5, 5),
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.camera),
            label: 'Camera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.upload_file),
            label: 'Uploads',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.accessibility),
            label: 'Sign-Lang',
          ),
        ],
      ),
    );
  }
}

// Top Navigator
AppBar buildAppBar(BuildContext context) {
  return AppBar(
    backgroundColor:
        Color.fromARGB(255, 35, 146, 236), // Change color for the Navigator
    leading: Icon(Icons.person, color: Colors.black),
    elevation: 0,
    actions: [
      IconButton(
        icon: Icon(Icons.settings, color: Colors.black),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SettingsPage()),
          );
        },
      ),
    ],
  );
}

// HomePage with real-time translation functionalities
class HomePage extends StatefulWidget {
  final CameraDescription camera;

  const HomePage({Key? key, required this.camera}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool isArabic = true;
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isRecording = false;
  VideoPlayerController? _videoPlayerController;
  bool _isProcessing = false;
  String _prediction = '';
  double _confidence = 0.0;
  Timer? _timer; // Timer for periodic recording

  @override
  void initState() {
    super.initState();
    // Camera initialization is handled when "Start" is pressed
  }

  // Initialize camera
  Future<void> _initializeCamera() async {
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController.initialize();
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      print("Error initializing camera: $e");
      setState(() {
        _prediction = 'Error initializing camera.';
      });
    }
  }

  // Dispose camera controller and timer
  @override
  void dispose() {
    _cameraController.dispose();
    _videoPlayerController?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // Toggle language
  void toggleLanguage() {
    setState(() {
      isArabic = !isArabic;
    });
  }

  // Record video segment
  Future<String?> _recordVideoSegment() async {
    if (!_isCameraInitialized) return null;

    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String videoPath =
          '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.mp4';

      await _cameraController.startVideoRecording();

      // Record for 5 seconds
      await Future.delayed(Duration(seconds: 5));

      XFile videoFile = await _cameraController.stopVideoRecording();

      // Move the video to the desired path
      final File savedVideo = await File(videoFile.path).copy(videoPath);

      return savedVideo.path;
    } catch (e) {
      print("Error recording video segment: $e");
      setState(() {
        _prediction = 'Error recording video segment.';
      });
      return null;
    }
  }

  // Play the recorded video
  Future<void> _playVideo(String path) async {
    _videoPlayerController = VideoPlayerController.file(File(path));
    await _videoPlayerController!.initialize();
    setState(() {});
    await _videoPlayerController!.setLooping(false);
    await _videoPlayerController!.play();
  }

  // Upload video to Flask backend
  Future<void> _uploadVideo(String path) async {
    setState(() {
      _isProcessing = true;
      _prediction = '';
      _confidence = 0.0;
    });

    try {
      String url = getBackendUrl(); // Get the dynamic backend URL
      debugPrint("Uploading video to: $url"); // For debugging purposes

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(url),
      );

      request.files.add(await http.MultipartFile.fromPath('video', path));

      var response = await request.send();

      debugPrint("Response status: ${response.statusCode}"); // Debugging

      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var jsonResponse = json.decode(responseData);
        setState(() {
          _prediction = jsonResponse['predicted_label'];
          _confidence = jsonResponse['confidence'];
        });
        debugPrint(
            "Prediction: $_prediction, Confidence: $_confidence"); // Debugging
      } else {
        setState(() {
          _prediction = 'Error: ${response.statusCode}';
          _confidence = 0.0;
        });
        debugPrint("Error: ${response.statusCode}"); // Debugging
      }
    } catch (e) {
      print("Error uploading video: $e");
      setState(() {
        _prediction = 'Error: ${e.toString()}';
        _confidence = 0.0;
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Start the real-time translation process
  void _startRealTimeTranslation() async {
    await _initializeCamera();

    if (!_isCameraInitialized) return;

    setState(() {
      _isRecording = true;
      _prediction = 'Starting real-time translation...';
      _confidence = 0.0;
    });

    // Start a periodic timer to record and upload video segments
    _timer = Timer.periodic(Duration(seconds: 6), (timer) async {
      String? videoPath = await _recordVideoSegment();
      if (videoPath != null) {
        await _playVideo(videoPath);
        await _uploadVideo(videoPath);
      } else {
        print("Failed to record video segment.");
      }
    });
  }

  // Stop the real-time translation process
  void _stopRealTimeTranslation() {
    _timer?.cancel();
    _timer = null;

    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    setState(() {
      _isRecording = false;
      _prediction = 'Real-time translation stopped.';
      _confidence = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Language toggle button
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LanguageToggleButton(
                  label: isArabic ? "العربية" : "English",
                ),
                IconButton(
                  icon: Icon(Icons.swap_horiz),
                  onPressed: toggleLanguage,
                ),
                LanguageToggleButton(
                  label: isArabic ? "English" : "العربية",
                ),
              ],
            ),
          ),
          // Camera preview or video playback
          Expanded(
            child: Center(
              child: Container(
                width: 370,
                height: 500,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(45),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: Offset(4, 4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.9),
                      offset: Offset(-4, -4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: _isRecording
                    ? (_isCameraInitialized
                        ? (_videoPlayerController != null &&
                                _videoPlayerController!.value.isInitialized
                            ? AspectRatio(
                                aspectRatio:
                                    _videoPlayerController!.value.aspectRatio,
                                child: VideoPlayer(_videoPlayerController!),
                              )
                            : CameraPreview(_cameraController))
                        : Center(child: CircularProgressIndicator()))
                    : Center(
                        child: Icon(
                          Icons.camera_alt,
                          size: 100,
                          color: Colors.grey[400],
                        ),
                      ),
              ),
            ),
          ),
          // Start/Stop button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isRecording ? Colors.red : Colors.green, // Button color
                minimumSize: Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              onPressed: () {
                if (_isRecording) {
                  _stopRealTimeTranslation();
                } else {
                  _startRealTimeTranslation();
                }
              },
              child: Text(
                _isRecording ? "Stop" : "Start",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
          // Translation box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.0),
            child: Container(
              width: double.infinity,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(29),
              ),
              child: Center(
                child: _isProcessing
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text(
                            'Processing... Please wait.',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[800]),
                          ),
                        ],
                      )
                    : _prediction.isNotEmpty
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Prediction: $_prediction',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Confidence: ${(_confidence * 100).toStringAsFixed(2)}%',
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          )
                        : Text(
                            'Translation will appear here...',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[800]),
                            textAlign: TextAlign.center,
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Language Toggle Button Widget
class LanguageToggleButton extends StatelessWidget {
  final String label;

  const LanguageToggleButton({Key? key, required this.label}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 5,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 16),
      ),
    );
  }
}

class UploadPage extends StatefulWidget {
  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  String _translatedText = 'Translation will appear here...';
  String _displayedContent = 'No content uploaded or recorded';

  void _uploadFile() {
    setState(() {
      _translatedText = 'Uploaded file translation';
      _displayedContent = 'Uploaded Content Preview';
    });
  }

  void _recordAudio() {
    setState(() {
      _translatedText = 'Recorded audio translation';
      _displayedContent = 'Recorded Audio Preview';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color.fromARGB(255, 35, 146, 236),
        leading: Icon(Icons.person, color: Colors.black),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // قسم الأزرار (Upload و Record) في الأعلى
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    GestureDetector(
                      onTap: _uploadFile,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          color: Colors.grey[300],
                        ),
                        child: Center(
                          child: Icon(Icons.upload_file,
                              size: 40, color: Colors.grey[600]),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextButton(
                      onPressed: _uploadFile,
                      child: Text("Upload"),
                    ),
                  ],
                ),
                Column(
                  children: [
                    GestureDetector(
                      onTap: _recordAudio,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          color: Colors.grey[300],
                        ),
                        child: Center(
                          child: Icon(Icons.mic,
                              size: 40, color: Colors.grey[600]),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextButton(
                      onPressed: _recordAudio,
                      child: Text("Record"),
                    ),
                  ],
                ),
              ],
            ),

            // إضافة مسافة بين الأزرار والصورة
            SizedBox(height: 30),

            // where the upload and Record will show
            Container(
              width: double.infinity,
              height: 500,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  _displayedContent,
                  style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // used to put the box down
            Spacer(),

            // translate box
            Container(
              width: double.infinity,
              height: 150,
              padding: EdgeInsets.all(0),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  _translatedText,
                  style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// صفحة الإشارات اليدوية مع تكبير الصور وعدد الأحرف من A إلى Z
class HandSignPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a Hand Sign:',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // Number of columns
                  mainAxisSpacing: 10.0,
                  crossAxisSpacing: 10.0,
                  childAspectRatio: 1, // Aspect ratio
                ),
                itemCount: 26, // From A to Z (26 letters)
                itemBuilder: (context, index) {
                  return Column(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.grey[300],
                        ),
                        child: Center(
                          child: Text(
                            String.fromCharCode(65 + index), // Letter A to Z
                            style: TextStyle(
                                fontSize: 40, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Sign ${String.fromCharCode(65 + index)}', // Named the letter
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// صفحة الإعدادات (بدون تغيير)
class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfilePhoto(),
            SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.brightness_6),
              title: Text('Dark Mode'),
              trailing: Switch(value: false, onChanged: (val) {}),
            ),
            ListTile(
              leading: Icon(Icons.language),
              title: Text('Language'),
              trailing: DropdownButton<String>(
                value: 'English',
                onChanged: (String? newValue) {},
                items: <String>['English', 'Arabic']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// صورة الملف الشخصي في الإعدادات
class ProfilePhoto extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage: NetworkImage(
              'https://your-image-url.com/profile.jpg',
            ),
            backgroundColor: Colors.grey[200],
          ),
          SizedBox(height: 10),
          Text(
            'Muhannad Jamoul',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
