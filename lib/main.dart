import 'dart:async';
import 'dart:convert';

import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences data key.
const EVENTS_KEY = "fetch_events";

/// This "Headless Task" is run when app is terminated.
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  var taskId = task.taskId;
  var timeout = task.timeout;
  if (timeout) {
    print("[BackgroundFetch] Headless task timed-out: $taskId");
    BackgroundFetch.finish(taskId);
    return;
  }

  print("[BackgroundFetch] Headless event received: $taskId");

  var timestamp = DateTime.now();

  var prefs = await SharedPreferences.getInstance();

  // 从 SharedPreferences 中读取 fetch_events
  var events = <String>[];
  var json = prefs.getString(EVENTS_KEY);
  if (json != null) {
    events = jsonDecode(json).cast<String>();
  }
  // 添加新事件。
  events.insert(0, "$taskId@$timestamp [Headless]");
  // 在 SharedPreferences 中持久化 fetch 事件
  prefs.setString(EVENTS_KEY, jsonEncode(events));

  if (taskId == 'flutter_background_fetch') {
    BackgroundFetch.scheduleTask(TaskConfig(
        taskId: "com.transistorsoft.customtask",
        delay: 5000,
        periodic: false,
        forceAlarmManager: false,
        stopOnTerminate: false,
        enableHeadless: true
    ));
  }
  BackgroundFetch.finish(taskId);
}

void main() {
  // 使用 Flutter Driver 扩展启用集成测试。
  // 请参阅 https://flutter.io/testing/ 了解更多信息。
  runApp(MyApp());

  // 注册以在应用程序终止后接收 BackgroundFetch 事件。
  // 需要 {stopOnTerminate: false, enableHeadless: true}
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _enabled = true;
  int _status = 0;
  List<String> _events = [];

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // 平台消息是異步的，所以我們在異步方法中進行初始化。
  Future<void> initPlatformState() async {
    // 從 SharedPreferences 加載持久獲取事件
    var prefs = await SharedPreferences.getInstance();
    var json = prefs.getString(EVENTS_KEY);
    if (json != null) {
      setState(() {
        _events = jsonDecode(json).cast<String>();
      });
    }

    // 配置BackgroundFetch。
    try {
      var status = await BackgroundFetch.configure(BackgroundFetchConfig(
          minimumFetchInterval: 15,
          forceAlarmManager: false,
          stopOnTerminate: false,
          startOnBoot: true,
          enableHeadless: true,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresStorageNotLow: false,
          requiresDeviceIdle: false,
          requiredNetworkType: NetworkType.NONE
      ), _onBackgroundFetch, _onBackgroundFetchTimeout);
      print('[BackgroundFetch] configure success: $status');
      setState(() {
        _status = status;
      });

      // 在 10000 毫秒内安排一个“一次性”自定义任务。
      // 这些在 Android 上相当可靠（尤其是使用 forceAlarmManager），但在 iOS 上不可靠，
      // 必须为设备供电的地方（并且延迟将被操作系统限制）。
      BackgroundFetch.scheduleTask(TaskConfig(
          taskId: "com.transistorsoft.customtask",
          delay: 10000,
          periodic: false,
          forceAlarmManager: true,
          stopOnTerminate: false,
          enableHeadless: true
      ));
    } on Exception catch(e) {
      print("[BackgroundFetch] configure ERROR: $e");
    }

    // 如果小部件在异步平台时从树中移除
    // 消息在传输中，我们想丢弃回复而不是调用
    // setState 更新我们不存在的外观。
    if (!mounted) return;
  }

  void _onBackgroundFetch(String taskId) async {
    var prefs = await SharedPreferences.getInstance();
    var timestamp = DateTime.now();
    // This is the fetch-event callback.
    print("[BackgroundFetch] Event received: $taskId");
    setState(() {
      _events.insert(0, "$taskId@${timestamp.toString()}");
    });
    // 在 SharedPreferences 中持久化 fetch 事件
    prefs.setString(EVENTS_KEY, jsonEncode(_events));

    if (taskId == "flutter_background_fetch") {
      // 在接收到 fetch 事件时安排一次性任务（用于测试）。
      /*
      BackgroundFetch.scheduleTask(TaskConfig(
          taskId: "com.transistorsoft.customtask",
          delay: 5000,
          periodic: false,
          forceAlarmManager: true,
          stopOnTerminate: false,
          enableHeadless: true,
          requiresNetworkConnectivity: true,
          requiresCharging: true
      ));
       */
    }
    // 重要提示：您必须发出获取任务完成的信号，否则操作系统会惩罚您的应用
    // 因为在后台花费的时间太长。
    BackgroundFetch.finish(taskId);
  }

  /// 此事件在您的任务即将超时前不久触发。 您必须完成所有未完成的工作并调用 BackgroundFetch.finish(taskId)。
  void _onBackgroundFetchTimeout(String taskId) {
    print("[BackgroundFetch] TIMEOUT: $taskId");
    BackgroundFetch.finish(taskId);
  }

  void _onClickEnable(enabled) {
    setState(() {
      _enabled = enabled;
    });
    if (enabled) {
      BackgroundFetch.start().then((status) {
        print('[BackgroundFetch] start success: $status');
      }).catchError((e) {
        print('[BackgroundFetch] start FAILURE: $e');
      });
    } else {
      BackgroundFetch.stop().then((status) {
        print('[BackgroundFetch] stop success: $status');
      });
    }
  }

  void _onClickStatus() async {
    var status = await BackgroundFetch.status;
    print('[BackgroundFetch] status: $status');
    setState(() {
      _status = status;
    });
  }

  void _onClickClear() async {
    var prefs = await SharedPreferences.getInstance();
    prefs.remove(EVENTS_KEY);
    setState(() {
      _events = [];
    });
  }
  @override
  Widget build(BuildContext context) {
    const EMPTY_TEXT = Center(child: Text('等待获取事件。 模拟一个。\n [Android] \$ ./scripts/simulate-fetch\n [iOS] XCode->Debug->Simulate Background Fetch'));

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
            title: const Text('BackgroundFetch Example', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.amberAccent,
            foregroundColor: Colors.black,
            actions: <Widget>[
              Switch(value: _enabled, onChanged: _onClickEnable),
            ]
        ),
        body: (_events.isEmpty) ? EMPTY_TEXT : ListView.builder(
            itemCount: _events.length,
            itemBuilder: (context, index) {
              var event = _events[index].split("@");
              return InputDecorator(
                  decoration: InputDecoration(
                      contentPadding: const EdgeInsets.only(left: 5.0, top: 5.0, bottom: 5.0),
                      labelStyle: const TextStyle(color: Colors.blue, fontSize: 20.0),
                      labelText: "[${event[0].toString()}]"
                  ),
                  child: Text(event[1], style: const TextStyle(color: Colors.black, fontSize: 16.0))
              );
            }
        ),
        bottomNavigationBar: BottomAppBar(
            child: Container(
                padding: const EdgeInsets.only(left: 5.0, right:5.0),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      ElevatedButton(onPressed: _onClickStatus, child: Text('Status: $_status')),
                      ElevatedButton(onPressed: _onClickClear, child: const Text('Clear'))
                    ]
                )
            )
        ),
      ),
    );
  }
}