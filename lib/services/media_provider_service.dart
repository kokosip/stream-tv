import 'moviebox_api_service.dart';
import 'fourkhdhub_api_service.dart';
import 'app_source_service.dart';

export 'moviebox_api_service.dart' show RateLimitException, NetworkConnectionException, NoStreamAvailableException, ApiException;

class MediaProviderService {
  final MovieBoxApiService _movieBox = MovieBoxApiService();
  final FourKHdHubApiService _fourKHdHub = FourKHdHubApiService();

  bool get isMovieBox => AppSourceService.isMovieBox;
  bool get isFourKHdHub => AppSourceService.isFourKHdHub;

  /// Get Homepage items
  Future<Map<String, dynamic>> getHomepage({int page = 1, int tabId = 0}) async {
    if (AppSourceService.isFourKHdHub) {
      return _fourKHdHub.getHomepage(page: page, tabId: tabId);
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
    return _movieBox.search(
      query: query,
      page: page,
      perPage: perPage,
      subjectType: subjectType,
    );
  }

  /// Get Details of a Movie/TV show
  Future<Map<String, dynamic>> getDetails({required String subjectId}) async {
    if (AppSourceService.isFourKHdHub) {
      return _fourKHdHub.getDetails(subjectId: subjectId);
    }
    return _movieBox.getDetails(subjectId: subjectId);
  }

  /// Get Season details for a TV show
  Future<Map<String, dynamic>> getSeasonInfo({required String subjectId}) async {
    if (AppSourceService.isFourKHdHub) {
      final details = await _fourKHdHub.getDetails(subjectId: subjectId);
      return details["seasons"] ?? {};
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
    if (AppSourceService.isFourKHdHub) {
      return _fourKHdHub.getResources(subjectId: subjectId, se: se, ep: ep);
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
    if (AppSourceService.isFourKHdHub) {
      return {"list": []};
    }
    return _movieBox.getExtCaptions(subjectId: subjectId, resourceId: resourceId);
  }
}
