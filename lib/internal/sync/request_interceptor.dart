import 'package:dio/dio.dart';
import 'package:potato_notes/internal/logger_provider.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/controller.dart';
import 'package:potato_notes/internal/utils.dart';

class RequestInterceptor extends InterceptorsWrapper with LoggerProvider {
  @override
  Future onRequest(RequestOptions options, RequestInterceptorHandler h) async {
    logger.v(
      "Going to send ${options.method.toUpperCase()} to ${options.uri.toString()}",
    );
    final Map<String, dynamic> headers = options.headers;
    final bool useToken = headers["useToken"] == true;
    final bool useRefreshToken = headers["useRefreshToken"] == true;

    if (useToken) {
      headers.remove("useToken");
      final String? token = prefs.accessToken;
      headers.putIfAbsent("Authorization", () => "Bearer $token");
    } else if (useRefreshToken) {
      headers.remove("useRefreshToken");
      final String? token = prefs.refreshToken;
      headers.putIfAbsent("Authorization", () => "Bearer $token");
    }

    return super.onRequest(options.copyWith(headers: headers), h);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler h) {
    final List<String> uriParts =
        response.realUri.toString().replaceFirst(prefs.apiUrl, "").split("/");
    uriParts.removeAt(0);
    logger.v(
      "(${response.requestOptions.method.toUpperCase()} /${uriParts.join("/")}) Server responded!",
    );
    super.onResponse(response, h);
  }

  @override
  Future onError(DioError err, ErrorInterceptorHandler h) async {
    if (err.response?.statusCode == 401) {
      final AuthResponse response = await Controller.account.refreshToken();
      if (response.status) {
        final Options options = Options(
          method: err.requestOptions.method,
          sendTimeout: err.requestOptions.sendTimeout,
          receiveTimeout: err.requestOptions.receiveTimeout,
          extra: err.requestOptions.extra,
          headers: Utils.asMap<String, dynamic>(err.requestOptions.headers
            ..update("Authorization", (value) => prefs.accessToken)),
          responseType: err.requestOptions.responseType,
          contentType: err.requestOptions.contentType,
          validateStatus: err.requestOptions.validateStatus,
          receiveDataWhenStatusError:
              err.requestOptions.receiveDataWhenStatusError,
          followRedirects: err.requestOptions.followRedirects,
          maxRedirects: err.requestOptions.maxRedirects,
          requestEncoder: err.requestOptions.requestEncoder,
          responseDecoder: err.requestOptions.responseDecoder,
          listFormat: err.requestOptions.listFormat,
        );

        return dio.request(
          err.requestOptions.path,
          options: options,
          onReceiveProgress: err.requestOptions.onReceiveProgress,
          onSendProgress: err.requestOptions.onSendProgress,
        );
      }
    }
    return super.onError(err, h);
  }
}
