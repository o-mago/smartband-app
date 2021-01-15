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
      bleChar.write([229, 17]);
      Timer(Duration(seconds: 40), () {
        bleChar.write([199, 17]);
        Timer(Duration(seconds: 40), () {
          bleChar.write([36, 1]);
        });
      });
    });
  }

  List<int> _getRandomBytes() {
    final math = Random();
    return [
      math.nextInt(255),
      math.nextInt(255),
      math.nextInt(255),
      math.nextInt(255)
    ];
  }

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
      if (services[i].uuid.toString().toUpperCase().substring(4, 8) == "55FF") {
        List<BluetoothService> serviceList = [services[i]];
        for (var j = 0; j < services[i].characteristics.length; j++) {
          if (services[i]
                  .characteristics[j]
                  .uuid
                  .toString()
                  .toUpperCase()
                  .substring(4, 8) ==
              "33F2") {
            List<BluetoothCharacteristic> characteristicList = [
              services[i].characteristics[j]
            ];
            if (!characteristicList[0].isNotifying) {
              print("TESTANDO");
              characteristicList[0].setNotifyValue(true);
              characteristicList[0].value.listen((event) {
                postData(event.toList());
              });
            }
            // widgets.addAll(serviceList
            //     .map((s) => ServiceTile(
            //           service: services[i],
            //           characteristicTiles: characteristicList
            //               .map(
            //                 (c) => CharacteristicTile(
            //                   characteristic: c,
            //                   onReadPressed: () => c.read(),
            //                   onWritePressed: () async {
            //                     await c.write(_getRandomBytes(),
            //                         withoutResponse: true);
            //                     await c.read();
            //                   },
            //                   onNotificationPressed: () async {
            //                     await c.setNotifyValue(!c.isNotifying);
            //                     await c.read();
            //                   },
            //                   descriptorTiles: c.descriptors
            //                       .map(
            //                         (d) => DescriptorTile(
            //                           descriptor: d,
            //                           onReadPressed: () => d.read(),
            //                           onWritePressed: () =>
            //                               d.write(_getRandomBytes()),
            //                         ),
            //                       )
            //                       .toList(),
            //                 ),
            //               )
            //               .toList(),
            //         ))
            //     .toList());
          }
          if (services[i]
                  .characteristics[j]
                  .uuid
                  .toString()
                  .toUpperCase()
                  .substring(4, 8) ==
              "33F1") {
            var characteristicWrite = services[i].characteristics[j];
            widgets.add(new Container(
                margin: const EdgeInsets.all(10.0),
                child: FloatingActionButton(
                  onPressed: () {
                    characteristicWrite.write([229, 17]);
                  },
                  child: Icon(Icons.favorite, color: Colors.red),
                  backgroundColor: Colors.white,
                )));

            widgets.add(new Container(
                margin: const EdgeInsets.all(10.0),
                child: FloatingActionButton(
                  onPressed: () {
                    characteristicWrite.write([199, 17]);
                  },
                  child: Icon(Icons.compass_calibration, color: Colors.blue),
                  backgroundColor: Colors.white,
                )));

            widgets.add(new Container(
                margin: const EdgeInsets.all(10.0),
                child: FloatingActionButton(
                  onPressed: () {
                    characteristicWrite.write([36, 1]);
                  },
                  child: Icon(Icons.copyright_outlined, color: Colors.orange),
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

  // List<Widget> _buildServiceTiles(List<BluetoothService> services) {
  //   return services
  //       .map(
  //         (s) => ServiceTile(
  //           service: s,
  //           characteristicTiles: s.characteristics
  //               .map(
  //                 (c) => CharacteristicTile(
  //                   characteristic: c,
  //                   onReadPressed: () => c.read(),
  //                   onWritePressed: () async {
  //                     await c.write(_getRandomBytes(), withoutResponse: true);
  //                     await c.read();
  //                   },
  //                   onNotificationPressed: () async {
  //                     await c.setNotifyValue(!c.isNotifying);
  //                     await c.read();
  //                   },
  //                   descriptorTiles: c.descriptors
  //                       .map(
  //                         (d) => DescriptorTile(
  //                           descriptor: d,
  //                           onReadPressed: () => d.read(),
  //                           onWritePressed: () => d.write(_getRandomBytes()),
  //                         ),
  //                       )
  //                       .toList(),
  //                 ),
  //               )
  //               .toList(),
  //         ),
  //       )
  //       .toList();
  // }

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
