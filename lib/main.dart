import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Memo App', // Changed title
      theme: ThemeData(
        primarySwatch: Colors.blue, // Use primarySwatch instead of colorScheme
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const VoiceMemoHomePage(title: 'Voice Memos'), // Changed home widget and title
    );
  }
}

// Renamed MyHomePage to VoiceMemoHomePage and made significant changes
class VoiceMemoHomePage extends StatefulWidget {
  const VoiceMemoHomePage({super.key, required this.title});

  final String title;

  @override
  State<VoiceMemoHomePage> createState() => _VoiceMemoHomePageState();
}

class _VoiceMemoHomePageState extends State<VoiceMemoHomePage> {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _filePath;
  List<String> _recordings = [];
  StreamSubscription? _recorderSubscription;
  StreamSubscription? _playerSubscription;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentlyPlaying;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _init(); // Keep _init for player/recorder setup and storage permission
    _loadRecordings();
    initializeDateFormatting(); // Initialize date formatting
  }

  Future<void> _init() async {
    // Request only storage permission here initially
    // Note: On modern Android/iOS, app-specific storage often doesn't require explicit permission.
    // This request might be more relevant for older Android versions or specific use cases.
    // Consider if you strictly need WRITE_EXTERNAL_STORAGE/READ_EXTERNAL_STORAGE.
    // final storageStatus = await Permission.storage.request();

    // if (storageStatus != PermissionStatus.granted) {
    //   // Handle storage permission denial if necessary
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text('Storage permission is recommended for saving recordings.')),
    //   );
    // }

    // Open recorder and player without checking mic permission here
    // Handle potential errors during opening
    try {
      await _recorder!.openRecorder();
      await _player!.openPlayer();
    } catch (e) {
       print('Error opening recorder/player: $e');
       // Show an error message to the user if needed
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Error initializing audio components.')),
       );
    }


    // Subscribe to recorder updates for timer
    _recorderSubscription = _recorder!.onProgress?.listen((e) { // Use null-aware access
      if (mounted) { // Check if the widget is still in the tree
        setState(() {
          _duration = e.duration;
        });
      }
    });

    // Subscribe to player updates
    _playerSubscription = _player!.onProgress?.listen((e) { // Use null-aware access
       if (mounted) { // Check if the widget is still in the tree
        setState(() {
          _position = e.position;
          _duration = e.duration; // Update duration based on player
        });
        if (e.position >= e.duration && e.duration > Duration.zero) { // Avoid calling stop multiple times
          _stopPlayback(); // Stop when playback finishes
        }
      }
    });
  }

  Future<void> _loadRecordings() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync();
    setState(() {
      _recordings = files
          .where((file) => file.path.endsWith('.aac')) // Filter for audio files
          .map((file) => file.path)
          .toList();
      _recordings.sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync())); // Sort by date
    });
  }


  @override
  void dispose() {
    _recorderSubscription?.cancel();
    _playerSubscription?.cancel();
    // Use null-aware calls
    _recorder?.closeRecorder();
    _player?.closePlayer();
    _recorder = null;
    _player = null;
    super.dispose();
  }

  Future<void> _startRecording() async {
    // --- Request Microphone Permission ---
    final micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      // Show a more informative dialog if permission is permanently denied
      if (micStatus == PermissionStatus.permanentlyDenied) {
         showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Microphone Permission Required'),
              content: const Text('Microphone permission has been permanently denied. Please enable it in app settings to record audio.'),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: const Text('Open Settings'),
                  onPressed: () {
                    openAppSettings(); // From permission_handler package
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to record audio.')),
        );
      }
      return; // Don't start recording if permission denied
    }
    // --- End Permission Request ---

    // Ensure recorder is open (it might fail in _init or be closed)
    if (_recorder == null || _recorder!.isStopped) {
       try {
         await _recorder?.closeRecorder(); // Close if needed
         await _recorder?.openRecorder(); // Re-open
       } catch (e) {
         print('Error re-opening recorder: $e');
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Could not start recorder. Please try again.')),
         );
         return;
       }
    }
    // Defensive check if recorder is still null after trying to open
    if (_recorder == null) return;


    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    _filePath = '${directory.path}/recording_$timestamp.aac'; // Use timestamp in filename

    try {
      await _recorder!.startRecorder(
        toFile: _filePath,
        codec: Codec.aacADTS,
      );
      if (mounted) {
        setState(() {
          _isRecording = true;
          _duration = Duration.zero; // Reset duration
        });
      }
    } catch (e) {
       print('Error starting recorder: $e');
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Failed to start recording.')),
       );
       if (mounted) {
         setState(() {
           _isRecording = false; // Ensure state is correct on error
         });
       }
    }
  }

  Future<void> _stopRecording() async {
    await _recorder!.stopRecorder();
    setState(() {
      _isRecording = false;
      _duration = Duration.zero; // Reset duration after stopping
    });
    _loadRecordings(); // Refresh the list after recording
  }

  Future<void> _startPlayback(String path) async {
    try {
      if (_isPlaying && _currentlyPlaying == path) {
        await _player?.resumePlayer(); // Use null-aware
      } else {
        if (_isPlaying) { // Stop previous playback if any
          await _stopPlayback(resetState: false); // Don't reset UI immediately
        }
        await _player?.startPlayer( // Use null-aware
          fromURI: path,
          codec: Codec.aacADTS,
          whenFinished: () {
            if (mounted) { // Check mounted before setState in callback
              _stopPlayback();
            }
          },
        );
        if (mounted) {
          setState(() {
            _isPlaying = true;
            _currentlyPlaying = path;
            _position = Duration.zero; // Reset position
          });
        }
      }
    } catch (e) {
      print('Error during playback: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error playing audio.')),
      );
      if (mounted) {
        _stopPlayback(); // Reset state on error
      }
    }
  }

  Future<void> _pausePlayback() async {
    try {
      await _player?.pausePlayer(); // Use null-aware
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
    } catch (e) {
      print('Error pausing playback: $e');
    }
  }

  Future<void> _stopPlayback({bool resetState = true}) async {
    try {
      await _player?.stopPlayer(); // Use null-aware
    } catch (e) {
      print('Error stopping playback: $e');
    } finally { // Ensure state is reset even if stopPlayer throws error
      if (resetState && mounted) {
        setState(() {
          _isPlaying = false;
          _currentlyPlaying = null;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
      }
    }
  }

  Future<void> _deleteRecording(String path) async {
     if (_isPlaying && _currentlyPlaying == path) {
      await _stopPlayback(); // Stop playback if deleting the current file
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    _loadRecordings(); // Refresh the list
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _getFileName(String path) {
    return path.split('/').last;
  }

  String _getFormattedDate(String path) {
    try {
      final file = File(path);
      final dateTime = file.lastModifiedSync();
      // Format: Month Day, Year HH:MM AM/PM (e.g., May 04, 2025 03:15 PM)
      return DateFormat('MMM dd, yyyy hh:mm a').format(dateTime);
    } catch (e) {
      return "Unknown Date"; // Handle potential errors reading file metadata
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary, // Use theme color
      ),
      body: Column(
        children: [
          // Recording Status/Timer
          if (_isRecording || _isPlaying)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _isRecording
                    ? 'Recording: ${_formatDuration(_duration)}'
                    : 'Playing: ${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          // Recordings List
          Expanded(
            child: _recordings.isEmpty
                ? const Center(child: Text('No recordings yet.'))
                : ListView.builder(
                    itemCount: _recordings.length,
                    itemBuilder: (context, index) {
                      final recordingPath = _recordings[index];
                      final isCurrentlyPlaying = _currentlyPlaying == recordingPath;
                      return ListTile(
                        title: Text(_getFileName(recordingPath)),
                        subtitle: Text(_getFormattedDate(recordingPath)), // Show formatted date
                        leading: IconButton(
                          icon: Icon(isCurrentlyPlaying && _isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: () {
                            if (isCurrentlyPlaying && _isPlaying) {
                              _pausePlayback();
                            } else {
                              _startPlayback(recordingPath);
                            }
                          },
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteRecording(recordingPath),
                        ),
                        // Add progress indicator for playing item
                        selected: isCurrentlyPlaying, // Highlight playing item
                        selectedTileColor: Colors.blue.withOpacity(0.1),
                      );
                    },
                  ),
          ),
          // Recording Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FloatingActionButton(
              onPressed: _recorder!.isRecording ? _stopRecording : _startRecording,
              tooltip: _isRecording ? 'Stop Recording' : 'Start Recording',
              backgroundColor: _isRecording ? Colors.red : Colors.blue,
              child: Icon(_isRecording ? Icons.stop : Icons.mic),
            ),
          ),
        ],
      ),
    );
  }
}
