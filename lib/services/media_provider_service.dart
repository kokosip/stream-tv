import 'moviebox_api_service.dart';
import 'fourkhdhub_api_service.dart';
import 'dramachi_api_service.dart';
import 'pusatfilm_api_service.dart';
import 'juraganfilm_api_service.dart';
import 'samehadaku_api_service.dart';
import 'otakudesu_api_service.dart';
import 'anichin_api_service.dart';
import 'dracinsi_api_service.dart';
import 'drakorkita_api_service.dart';
import 'sorastream_api_service.dart';
import 'app_source_service.dart';

export 'moviebox_api_service.dart' show RateLimitException, NetworkConnectionException, NoStreamAvailableException, ApiException;

class MediaProviderService {
  final MovieBoxApiService _movieBox = MovieBoxApiService();
  final FourKHdHubApiService _fourKHdHub = FourKHdHubApiService();
  final DramachiApiService _dramachi = DramachiApiService();
  final PusatfilmApiService _pusatfilm = PusatfilmApiService();
  final JuraganfilmApiService _juraganfilm = JuraganfilmApiService();
  final SamehadakuApiService _samehadaku = SamehadakuApiService();
  final OtakudesuApiService _otakudesu = OtakudesuApiService();
  final AnichinApiService _anichin = AnichinApiService();
  final DracinSiApiService _dracinsi = DracinSiApiService();
  final DrakorkitaApiService _drakorkita = DrakorkitaApiService();
  final SorastreamApiService _sorastream = SorastreamApiService();

  bool get isMovieBox => AppSourceService.isMovieBox;
  bool get isFourKHdHub => AppSourceService.isFourKHdHub;
  bool get isDramachi => AppSourceService.isDramachi;
  bool get isPusatFilm => AppSourceService.isPusatFilm;
  bool get isJuraganFilm => AppSourceService.isJuraganFilm;
  bool get isSamehadaku => AppSourceService.isSamehadaku;
  bool get isOtakudesu => AppSourceService.isOtakudesu;
  bool get isAnichin => AppSourceService.isAnichin;
  bool get isDracinSi => AppSourceService.isDracinSi;
  bool get isDrakorKita => AppSourceService.isDrakorKita;
  bool get isSoraStream => AppSourceService.isSoraStream;

  /// Get Homepage items
  Future<Map<String, dynamic>> getHomepage({int page = 1, int tabId = 0}) async {
    if (AppSourceService.isFourKHdHub) {
      return _fourKHdHub.getHomepage(page: page, tabId: tabId);
    }
    if (AppSourceService.isDramachi) {
      return _dramachi.getHomepage(page: page);
    }
    if (AppSourceService.isPusatFilm) {
      return _pusatfilm.getHomepage(page: page);
    }
    if (AppSourceService.isJuraganFilm) {
      return _juraganfilm.getHomepage(page: page);
    }
    if (AppSourceService.isSamehadaku) {
      return _samehadaku.getHomepage(page: page);
    }
    if (AppSourceService.isOtakudesu) {
      return _otakudesu.getHomepage(page: page);
    }
    if (AppSourceService.isAnichin) {
      return _anichin.getHomepage(page: page);
    }
    if (AppSourceService.isDracinSi) {
      return _dracinsi.getHomepage(page: page);
    }
    if (AppSourceService.isDrakorKita) {
      return _drakorkita.getHomepage(page: page);
    }
    if (AppSourceService.isSoraStream) {
      return _sorastream.getHomepage(page: page);
    }
    return _movieBox.getHomepage(page: page, tabId: tabId);
  }

  /// Search movies & TV shows
  Future<Map<String, dynamic>> search({
    required String query,
    int page = 1,
    int perPage = 20,
    int subjectType = 0,
  }) async {
    if (AppSourceService.isFourKHdHub) {
      return _fourKHdHub.search(query: query, page: page, subjectType: subjectType);
    }
    if (AppSourceService.isDramachi) {
      final list = await _dramachi.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    if (AppSourceService.isPusatFilm) {
      final list = await _pusatfilm.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    if (AppSourceService.isJuraganFilm) {
      final list = await _juraganfilm.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    if (AppSourceService.isSamehadaku) {
      final list = await _samehadaku.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    if (AppSourceService.isOtakudesu) {
      final list = await _otakudesu.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    if (AppSourceService.isAnichin) {
      final list = await _anichin.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    if (AppSourceService.isDracinSi) {
      final list = await _dracinsi.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    if (AppSourceService.isDrakorKita) {
      final list = await _drakorkita.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    if (AppSourceService.isSoraStream) {
      final list = await _sorastream.search(query, page: page);
      return {'code': 0, 'list': list, 'items': list, 'data': {'list': list}};
    }
    return _movieBox.search(
      query: query,
      page: page,
      perPage: perPage,
      subjectType: subjectType,
    );
  }

  /// Get Details of a Movie/TV show
  Future<Map<String, dynamic>> getDetails({required String subjectId}) async {
    if (AppSourceService.isFourKHdHub || subjectId.startsWith('4khdhub_')) {
      return _fourKHdHub.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isDramachi || subjectId.startsWith('dramachi_') || subjectId.contains('::')) {
      return _dramachi.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isPusatFilm || subjectId.startsWith('pusatfilm_')) {
      return _pusatfilm.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isJuraganFilm || subjectId.startsWith('juraganfilm_')) {
      return _juraganfilm.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isSamehadaku || subjectId.startsWith('samehadaku_')) {
      return _samehadaku.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isOtakudesu || subjectId.startsWith('otakudesu_')) {
      return _otakudesu.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isAnichin || subjectId.startsWith('anichin_')) {
      return _anichin.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isDracinSi || subjectId.startsWith('dracinsi_')) {
      return _dracinsi.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isDrakorKita || subjectId.startsWith('drakorkita_')) {
      return _drakorkita.getDetails(subjectId: subjectId);
    }
    if (AppSourceService.isSoraStream || subjectId.startsWith('sorastream_')) {
      return _sorastream.getDetails(subjectId: subjectId);
    }
    return _movieBox.getDetails(subjectId: subjectId);
  }

  /// Get Season details for a TV show
  Future<Map<String, dynamic>> getSeasonInfo({required String subjectId}) async {
    if (AppSourceService.isFourKHdHub || subjectId.startsWith('4khdhub_')) {
      final details = await _fourKHdHub.getDetails(subjectId: subjectId);
      return details["seasons"] ?? {};
    }
    if (AppSourceService.isDramachi || subjectId.startsWith('dramachi_') || subjectId.contains('::')) {
      final details = await _dramachi.getDetails(subjectId: subjectId);
      return {'seasons': details['seasons'] ?? []};
    }
    if (AppSourceService.isPusatFilm || subjectId.startsWith('pusatfilm_')) {
      return _pusatfilm.getSeasonInfo(subjectId: subjectId);
    }
    if (AppSourceService.isJuraganFilm || subjectId.startsWith('juraganfilm_')) {
      return _juraganfilm.getSeasonInfo(subjectId: subjectId);
    }
    if (AppSourceService.isSamehadaku || subjectId.startsWith('samehadaku_')) {
      return _samehadaku.getSeasonInfo(subjectId: subjectId);
    }
    if (AppSourceService.isOtakudesu || subjectId.startsWith('otakudesu_')) {
      return _otakudesu.getSeasonInfo(subjectId: subjectId);
    }
    if (AppSourceService.isAnichin || subjectId.startsWith('anichin_')) {
      return _anichin.getSeasonInfo(subjectId: subjectId);
    }
    if (AppSourceService.isDracinSi || subjectId.startsWith('dracinsi_')) {
      return _dracinsi.getSeasonInfo(subjectId: subjectId);
    }
    if (AppSourceService.isDrakorKita || subjectId.startsWith('drakorkita_')) {
      return _drakorkita.getSeasonInfo(subjectId: subjectId);
    }
    if (AppSourceService.isSoraStream || subjectId.startsWith('sorastream_')) {
      return _sorastream.getSeasonInfo(subjectId: subjectId);
    }
    return _movieBox.getSeasonInfo(subjectId: subjectId);
  }

  /// Get Streaming video resources
  Future<Map<String, dynamic>> getResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
    int resolution = 1080,
  }) async {
    if (AppSourceService.isFourKHdHub || subjectId.startsWith('4khdhub_')) {
      return _fourKHdHub.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isDramachi || subjectId.startsWith('dramachi_') || subjectId.contains('::')) {
      return _dramachi.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isPusatFilm || subjectId.startsWith('pusatfilm_')) {
      return _pusatfilm.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isJuraganFilm || subjectId.startsWith('juraganfilm_')) {
      return _juraganfilm.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isSamehadaku || subjectId.startsWith('samehadaku_')) {
      return _samehadaku.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isOtakudesu || subjectId.startsWith('otakudesu_')) {
      return _otakudesu.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isAnichin || subjectId.startsWith('anichin_')) {
      return _anichin.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isDracinSi || subjectId.startsWith('dracinsi_')) {
      return _dracinsi.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isDrakorKita || subjectId.startsWith('drakorkita_')) {
      return _drakorkita.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    if (AppSourceService.isSoraStream || subjectId.startsWith('sorastream_')) {
      return _sorastream.getResources(subjectId: subjectId, se: se, ep: ep);
    }
    return _movieBox.getResources(
      subjectId: subjectId,
      se: se,
      ep: ep,
      resolution: resolution,
    );
  }

  /// Resolve stream playback source (handles 4KHDHub HubCloud/PixelDrain resolving)
  Future<Map<String, dynamic>?> resolveRelease(Map<String, dynamic> resourceItem) async {
    if (AppSourceService.isFourKHdHub) {
      return _fourKHdHub.resolveRelease(resourceItem);
    }
    return null;
  }

  /// Get Subtitles for selected resource (MovieBox only)
  Future<Map<String, dynamic>> getExtCaptions({
    required String subjectId,
    required String resourceId,
  }) async {
    final isCustomProvider = AppSourceService.isFourKHdHub ||
        AppSourceService.isDramachi ||
        AppSourceService.isPusatFilm ||
        AppSourceService.isJuraganFilm ||
        AppSourceService.isSamehadaku ||
        AppSourceService.isOtakudesu ||
        AppSourceService.isAnichin ||
        AppSourceService.isDracinSi ||
        AppSourceService.isDrakorKita ||
        AppSourceService.isSoraStream ||
        subjectId.startsWith('pusatfilm_') ||
        subjectId.startsWith('juraganfilm_') ||
        subjectId.startsWith('samehadaku_') ||
        subjectId.startsWith('otakudesu_') ||
        subjectId.startsWith('anichin_') ||
        subjectId.startsWith('dracinsi_') ||
        subjectId.startsWith('drakorkita_') ||
        subjectId.startsWith('sorastream_') ||
        subjectId.startsWith('4khdhub_') ||
        subjectId.startsWith('dramachi_');

    if (isCustomProvider) {
      return {"list": []};
    }
    return _movieBox.getExtCaptions(subjectId: subjectId, resourceId: resourceId);
  }
}
