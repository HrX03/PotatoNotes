import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/controller.dart';
import 'package:potato_notes/internal/utils.dart';

class AccountController extends Controller {
  // used for registering a user, all it needs is username, email, password.
  // When there is an error it throws an exception which needs to be catched
  Future<AuthResponse> register(
      String username, String email, String password) async {
    final Map<String, String> body = {
      "username": username,
      "email": email,
      "password": password,
    };
    try {
      final Response registerResponse = await dio.post(
        url("user/register"),
        data: json.encode(body),
        options: Options(
          headers: {"Content-Type": "application/json"},
          validateStatus: (status) => true,
        ),
      );

      switch (registerResponse.statusCode) {
        case 200:
          return AuthResponse(status: true);
        default:
          return AuthResponse(
            status: false,
            message: registerResponse.data,
          );
      }
    } on SocketException {
      return AuthResponse(
        status: false,
        message: "Could not connect to auth server",
      );
    } catch (e) {
      if (e is DioError) {
        return AuthResponse(
          status: false,
          message: e.error.toString(),
        );
      }
      return AuthResponse(
        status: false,
        message: e.toString(),
      );
    }
  }

  // Logs in the user and puts tokens in shared_prefs
  // When there is an error it throws an exception which needs to be catched
  Future<AuthResponse> login(String emailOrUser, String password) async {
    Map<String, String> body;

    if (emailOrUser.contains(RegExp(".*..*@.*..*", dotAll: true))) {
      body = {
        "email": emailOrUser,
        "password": password,
      };
    } else {
      body = {
        "username": emailOrUser,
        "password": password,
      };
    }

    try {
      final Response loginResponse = await dio.post(
        url("user/login"),
        data: json.encode(body),
        options: Options(
          headers: {"Content-Type": "application/json"},
          validateStatus: (status) => true,
        ),
      );
      switch (loginResponse.statusCode) {
        case 200:
          final Map<String, String> response =
              Utils.asMap<String, String>(loginResponse.data);
          prefs.accessToken = response["token"];
          prefs.refreshToken = response["refresh_token"];
          await getUserInfo();
          return AuthResponse(status: true);
        default:
          logger.d(loginResponse.data);
          return AuthResponse(
            status: false,
            message: loginResponse.data,
          );
      }
    } on SocketException {
      return AuthResponse(
        status: false,
        message: "Could not connect to auth server",
      );
    } catch (e) {
      if (e is DioError) {
        return AuthResponse(
          status: false,
          message: e.error.toString(),
        );
      }
      return AuthResponse(
        status: false,
        message: e.toString(),
      );
    }
  }

  Future<AuthResponse> getUserInfo() async {
    final bool loggedIn = await syncRoutine.checkLoginStatus();

    if (loggedIn) {
      try {
        final Response profileRequest = await dio.get(
          url("user/profile"),
          options: Options(
            headers: Controller.tokenHeaders,
          ),
        );
        switch (profileRequest.statusCode) {
          case 200:
            final Map<String, Object?> response =
                Utils.asMap<String, Object?>(profileRequest.data);
            prefs.username = response["username"] as String?;
            prefs.email = response["email"] as String?;
            return AuthResponse(status: true);
          case 400:
            return AuthResponse(
              status: false,
              message: profileRequest.data,
            );
          default:
            throw "Unexpected response from auth server";
        }
      } on SocketException {
        throw "Could not connect to server";
      } catch (e) {
        rethrow;
      }
    } else {
      return AuthResponse(status: false, message: "Not logged in.");
    }
  }

  Future<void> logout() async {
    prefs.accessToken = null;
    prefs.refreshToken = null;
    prefs.username = null;
    prefs.email = null;
    prefs.lastUpdated = 0;
    prefs.avatarUrl = null;

    await tagHelper.deleteAllTags();
    await helper.deleteAllNotes();
  }

  // When the api the app uses returns a 401 (Unauthorized) this likely means the token is expired and needs to be refreshed
  // If the refreshing returns an exception with the body, it means it couldnt request access again
  // This means that the user needs to log back in.
  // When there is an error it throws an exception which needs to be catched
  Future<AuthResponse> refreshToken() async {
    Response refresh;

    if (prefs.refreshToken == null) {
      return AuthResponse(status: false, message: "Not logged in");
    }

    try {
      refresh = await dio.get(
        url("user/refresh"),
        options: Options(
          headers: Controller.refreshTokenHeaders,
        ),
      );
      switch (refresh.statusCode) {
        case 200:
          {
            prefs.accessToken = refresh.data["token"] as String;
            logger.d("accessToken: ${prefs.accessToken}", secure: true);
            return AuthResponse(status: true);
          }
        case 400:
          return AuthResponse(
            status: false,
            message: refresh.data,
          );
        default:
          throw "Unexpected response from auth server";
      }
    } on SocketException {
      throw "Could not connect to server";
    } catch (e) {
      rethrow;
    }
  }

  @override
  String get prefix => "login";
}
