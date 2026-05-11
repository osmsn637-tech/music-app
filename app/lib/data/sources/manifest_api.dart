import 'package:dio/dio.dart';

import '../models/remote_artist.dart';
import '../models/remote_song.dart';

class ManifestResult {
  const ManifestResult({
    required this.version,
    required this.songs,
    this.artists = const [],
  });

  final int version;
  final List<RemoteSong> songs;
  final List<RemoteArtist> artists;
}

class ConnectionTestResult {
  const ConnectionTestResult({
    required this.ok,
    required this.message,
    this.songCount,
    this.statusCode,
  });

  final bool ok;
  final String message;
  final int? songCount;
  final int? statusCode;
}

class ManifestApi {
  ManifestApi(this._dio);

  final Dio _dio;

  Future<ManifestResult> fetch(String baseUrl) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/manifest.json',
      options: Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Manifest body was empty');
    }
    final version = (data['version'] as num?)?.toInt() ?? 1;
    final rawSongs = (data['songs'] as List?) ?? const [];
    final songs = rawSongs
        .whereType<Map<String, dynamic>>()
        .map(RemoteSong.fromJson)
        .toList();
    final rawArtists = (data['artists'] as List?) ?? const [];
    final artists = rawArtists
        .whereType<Map<String, dynamic>>()
        .map(RemoteArtist.fromJson)
        .toList();
    return ManifestResult(
      version: version,
      songs: songs,
      artists: artists,
    );
  }

  Future<ConnectionTestResult> testConnection(String baseUrl) async {
    try {
      final result = await fetch(baseUrl);
      return ConnectionTestResult(
        ok: true,
        message: 'Connected. Found ${result.songs.length} songs.',
        songCount: result.songs.length,
        statusCode: 200,
      );
    } on DioException catch (e) {
      return ConnectionTestResult(
        ok: false,
        message: _humanizeDioError(e, baseUrl),
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ConnectionTestResult(ok: false, message: e.toString());
    }
  }

  String _humanizeDioError(DioException e, String baseUrl) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Timed out connecting to $baseUrl. Is the server running?';
      case DioExceptionType.connectionError:
        return 'Could not reach $baseUrl. Check your phone is on the same '
            'Wi-Fi as the server.';
      case DioExceptionType.badResponse:
        return 'Server returned ${e.response?.statusCode} for '
            '$baseUrl/manifest.json';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return e.message ?? 'Unknown error reaching $baseUrl';
    }
  }
}
