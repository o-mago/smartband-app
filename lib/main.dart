import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'globals.dart' as globals;

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:smartband_app/widgets.dart';
import 'package:cron/cron.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(FlutterBlueApp());
}

class FlutterBlueApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: Colors.lightBlue,
      home: StreamBuilder<BluetoothState>(
          stream: FlutterBlue.instance.state,
          initialData: BluetoothState.unknown,
          builder: (c, snapshot) {
            final state = snapshot.data;
            if (state == BluetoothState.on) {
              return FindDevicesScreen();
            }
            return BluetoothOffScreen(state: state);
          }),
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({Key key, this.state}) : super(key: key);

  final BluetoothState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bluetooth_disabled,
              size: 200.0,
              color: Colors.white54,
            ),
            Text(
              'Bluetooth Adapter is ${state != null ? state.toString().substring(15) : 'not available'}.',
              style: Theme.of(context)
                  .primaryTextTheme
                  .subhead
                  .copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class FindDevicesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Find Devices'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            FlutterBlue.instance.startScan(timeout: Duration(seconds: 4)),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              StreamBuilder<List<BluetoothDevice>>(
                stream: Stream.periodic(Duration(seconds: 2))
                    .asyncMap((_) => FlutterBlue.instance.connectedDevices),
                initialData: [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data
                      .map((d) => ListTile(
                            title: Text(d.name),
                            subtitle: Text(d.id.toString()),
                            trailing: StreamBuilder<BluetoothDeviceState>(
                              stream: d.state,
                              initialData: BluetoothDeviceState.disconnected,
                              builder: (c, snapshot) {
                                if (snapshot.data ==
                                    BluetoothDeviceState.connected) {
                                  return RaisedButton(
                                    child: Text('OPEN'),
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                DeviceScreen(device: d))),
                                  );
                                }
                                return Text(snapshot.data.toString());
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
              StreamBuilder<List<ScanResult>>(
                stream: FlutterBlue.instance.scanResults,
                initialData: [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data
                      .map(
                        (r) => ScanResultTile(
                          result: r,
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (context) {
                            r.device.connect();
                            return DeviceScreen(device: r.device);
                          })),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: FlutterBlue.instance.isScanning,
        initialData: false,
        builder: (c, snapshot) {
          if (snapshot.data) {
            return FloatingActionButton(
              child: Icon(Icons.stop),
              onPressed: () => FlutterBlue.instance.stopScan(),
              backgroundColor: Colors.red,
            );
          } else {
            return FloatingActionButton(
                child: Icon(Icons.search),
                onPressed: () => FlutterBlue.instance
                    .startScan(timeout: Duration(seconds: 4)));
          }
        },
      ),
    );
  }
}

class DeviceScreen extends StatelessWidget {
  DeviceScreen({Key key, this.device, bool synced}) : super(key: key);

  final cron = Cron();

  var arrived = false;

  var synced = false;

  final BluetoothDevice device;

  void setCronTask(BluetoothCharacteristic bleChar) {
    cron.schedule(Schedule.parse('*/5 * * * *'), () async {
      // Heart Beat
      bleChar.write([171, 0, 4, 255, 49, 9, 1]);
      Timer(Duration(seconds: 40), () {
        bleChar.write([171, 0, 4, 255, 49, 9, 0]);
        Timer(Duration(seconds: 10), () {
          // Pressure
          bleChar.write([171, 0, 4, 255, 49, 33, 1]);
          Timer(Duration(seconds: 60), () {
            bleChar.write([171, 0, 4, 255, 49, 33, 0]);
            Timer(Duration(seconds: 10), () {
              // Saturation
              bleChar.write([171, 0, 4, 255, 49, 17, 1]);
              Timer(Duration(seconds: 40), () {
                bleChar.write([171, 0, 4, 255, 49, 17, 0]);
                Timer(Duration(seconds: 10), () {
                  // Temperature
                  bleChar.write([171, 0, 4, 255, 134, 128, 1]);
                  Timer(Duration(seconds: 5), () {
                    bleChar.write([171, 0, 4, 255, 134, 128, 0]);
                  });
                });
              });
            });
          });
        });
      });
    });
  }

  DateTime lastMeasurementTime = new DateTime.now();

  Future<http.Response> postData(List<int> data) {
    arrived = true;
    return http.post(
      'https://smartbandback.herokuapp.com/api/v1/addData',
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, List<int>>{
        'data': data,
      }),
    );
  }

  List<Widget> _buildServiceTiles(List<BluetoothService> services) {
    List<Widget> widgets = new List<Widget>();
    for (var i = 0; i < services.length; i++) {
      if (services[i].uuid.toString().toUpperCase().substring(4, 8) == "0001") {
        for (var j = 0; j < services[i].characteristics.length; j++) {
          if (services[i]
                  .characteristics[j]
                  .uuid
                  .toString()
                  .toUpperCase()
                  .substring(4, 8) ==
              "0003") {
            List<BluetoothCharacteristic> characteristicList = [
              services[i].characteristics[j]
            ];
            if (!characteristicList[0].isNotifying) {
              characteristicList[0].setNotifyValue(true);
              characteristicList[0].value.listen((event) {
                // print(event.toList());
                if (DateTime.now().difference(lastMeasurementTime).inSeconds >
                    10) {
                  postData(event.toList());
                  lastMeasurementTime = new DateTime.now();
                }
              });
            }
          }
          if (services[i]
                  .characteristics[j]
                  .uuid
                  .toString()
                  .toUpperCase()
                  .substring(4, 8) ==
              "0002") {
            var characteristicWrite = services[i].characteristics[j];
            // Heart Beat
            widgets.add(new Container(
                margin: const EdgeInsets.all(10.0),
                child: FloatingActionButton(
                  onPressed: () {
                    characteristicWrite.write([171, 0, 4, 255, 49, 9, 1]);
                    Timer(Duration(seconds: 40), () {
                      characteristicWrite.write([171, 0, 4, 255, 49, 9, 0]);
                    });
                  },
                  child: Icon(Icons.favorite, color: Colors.red),
                  backgroundColor: Colors.white,
                )));
            // Pressure
            widgets.add(new Container(
                margin: const EdgeInsets.all(10.0),
                child: FloatingActionButton(
                  onPressed: () {
                    characteristicWrite.write([171, 0, 4, 255, 49, 33, 1]);
                    Timer(Duration(seconds: 60), () {
                      characteristicWrite.write([171, 0, 4, 255, 49, 33, 0]);
                    });
                  },
                  child: Icon(Icons.compass_calibration, color: Colors.blue),
                  backgroundColor: Colors.white,
                )));
            // Saturation
            widgets.add(new Container(
                margin: const EdgeInsets.all(10.0),
                child: FloatingActionButton(
                  onPressed: () {
                    characteristicWrite.write([171, 0, 4, 255, 49, 17, 1]);
                    Timer(Duration(seconds: 40), () {
                      characteristicWrite.write([171, 0, 4, 255, 49, 17, 0]);
                    });
                  },
                  child: Icon(Icons.copyright_outlined, color: Colors.orange),
                  backgroundColor: Colors.white,
                )));
            // Temperature
            widgets.add(new Container(
                margin: const EdgeInsets.all(10.0),
                child: FloatingActionButton(
                  onPressed: () {
                    characteristicWrite.write([171, 0, 4, 255, 134, 128, 1]);
                    Timer(Duration(seconds: 5), () {
                      characteristicWrite.write([171, 0, 4, 255, 134, 128, 0]);
                    });
                  },
                  child: Icon(Icons.alarm, color: Colors.pink),
                  backgroundColor: Colors.white,
                )));

            widgets.add(new Container(
                margin: const EdgeInsets.all(10.0),
                child: FloatingActionButton(
                  onPressed: () {
                    synced = !synced;
                    if (synced) {
                      setCronTask(characteristicWrite);
                    } else {
                      cron.close();
                    }
                    // setState(() => pressAttention = !pressAttention)
                  },
                  child: Icon(Icons.sync, color: Colors.green),
                  backgroundColor: synced ? Colors.grey : Colors.white,
                )));
          }
        }
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
        actions: <Widget>[
          StreamBuilder<BluetoothDeviceState>(
            stream: device.state,
            initialData: BluetoothDeviceState.connecting,
            builder: (c, snapshot) {
              VoidCallback onPressed;
              String text;
              switch (snapshot.data) {
                case BluetoothDeviceState.connected:
                  onPressed = () => device.disconnect();
                  text = 'DISCONNECT';
                  break;
                case BluetoothDeviceState.disconnected:
                  onPressed = () => device.connect();
                  text = 'CONNECT';
                  break;
                default:
                  onPressed = null;
                  text = snapshot.data.toString().substring(21).toUpperCase();
                  break;
              }
              return FlatButton(
                  onPressed: onPressed,
                  child: Text(
                    text,
                    style: Theme.of(context)
                        .primaryTextTheme
                        .button
                        .copyWith(color: Colors.white),
                  ));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            StreamBuilder<BluetoothDeviceState>(
              stream: device.state,
              initialData: BluetoothDeviceState.connecting,
              builder: (c, snapshot) => ListTile(
                leading: (snapshot.data == BluetoothDeviceState.connected)
                    ? Icon(Icons.bluetooth_connected)
                    : Icon(Icons.bluetooth_disabled),
                title: Text(
                    'Device is ${snapshot.data.toString().split('.')[1]}.'),
                subtitle: Text('${device.id}'),
                trailing: StreamBuilder<bool>(
                  stream: device.isDiscoveringServices,
                  initialData: false,
                  builder: (c, snapshot) => IndexedStack(
                    index: snapshot.data ? 1 : 0,
                    children: <Widget>[
                      IconButton(
                        icon: Icon(Icons.refresh),
                        onPressed: () => device.discoverServices(),
                      ),
                      IconButton(
                        icon: SizedBox(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.grey),
                          ),
                          width: 18.0,
                          height: 18.0,
                        ),
                        onPressed: null,
                      )
                    ],
                  ),
                ),
              ),
            ),
            // StreamBuilder<int>(
            //   stream: device.mtu,
            //   initialData: 0,
            //   builder: (c, snapshot) => ListTile(
            //     title: Text('MTU Size'),
            //     subtitle: Text('${snapshot.data} bytes'),
            //     trailing: IconButton(
            //       icon: Icon(Icons.edit),
            //       onPressed: () => device.requestMtu(223),
            //     ),
            //   ),
            // ),
            StreamBuilder<List<BluetoothService>>(
              stream: device.services,
              initialData: [],
              builder: (c, snapshot) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _buildServiceTiles(snapshot.data),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
