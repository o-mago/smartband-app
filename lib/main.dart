import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:smartband_app/database_helper.dart';

import 'globals.dart' as globals;

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:smartband_app/widgets.dart';
import 'package:cron/cron.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(FlutterBlueApp());
}

class FlutterBlueApp extends StatefulWidget {
  @override
  FlutterBlueAppState createState() => new FlutterBlueAppState();
}

class FlutterBlueAppState extends State<FlutterBlueApp> {
  String cpf = "";
  bool login = false;

  callback(value) {
    setState(() {
      cpf = value;
      login = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: Colors.lightBlue,
      home: StreamBuilder<BluetoothState>(
          stream: FlutterBlue.instance.state,
          initialData: BluetoothState.unknown,
          builder: (c, snapshot) {
            final state = snapshot.data;
            if (!login) {
              return LoginScreen(callback);
            }
            if (state == BluetoothState.on) {
              return FindDevicesScreen(cpf);
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
  FindDevicesScreen(this.cpf);

  final String cpf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Encontrar dispositivos'),
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
                                            builder: (context) => DeviceScreen(
                                                device: d, cpf: cpf))),
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
  DeviceScreen({Key key, this.device, bool synced, this.cpf}) : super(key: key);

  final cron = Cron();

  final String cpf;

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
    DatabaseHelper helper = DatabaseHelper.instance;
    arrived = true;
    if (data.length == 8 &&
        data[0] == 171 &&
        data[1] == 0 &&
        data[2] == 5 &&
        data[3] == 255 &&
        data[4] == 49 &&
        data[5] == 9 &&
        data[6] > 0) {
      HeartBeat heartBeat = HeartBeat();
      heartBeat.cpf = cpf;
      heartBeat.value = '${data[6]}';
      helper.insertHeartBeat(heartBeat);
    }
    // Pressure
    else if (data.length == 8 &&
        data[0] == 171 &&
        data[1] == 0 &&
        data[2] == 5 &&
        data[3] == 255 &&
        data[4] == 49 &&
        data[5] == 33 &&
        data[6] > 0) {
      Pressure pressure = Pressure();
      pressure.cpf = cpf;
      pressure.value = '${data[6]}:${data[7]}';
      helper.insertPressure(pressure);
    }
    // Saturation
    else if (data.length == 8 &&
        data[0] == 171 &&
        data[1] == 0 &&
        data[2] == 5 &&
        data[3] == 255 &&
        data[4] == 49 &&
        data[5] == 17 &&
        data[6] > 0) {
      Saturation saturation = Saturation();
      saturation.cpf = cpf;
      saturation.value = '${data[6]}';
      helper.insertSaturation(saturation);
    }
    // Temperature
    else if (data.length == 8 &&
        data[0] == 171 &&
        data[1] == 0 &&
        data[2] == 5 &&
        data[3] == 255 &&
        data[4] == 134 &&
        data[5] == 128 &&
        data[6] > 0) {
      Temperature temperature = Temperature();
      temperature.cpf = cpf;
      temperature.value = '${data[6]}';
      helper.insertTemperature(temperature);
    }
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
                  text = 'DESCONECTAR';
                  break;
                case BluetoothDeviceState.disconnected:
                  onPressed = () => device.connect();
                  text = 'CONECTAR';
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
                title: (snapshot.data == BluetoothDeviceState.connected)
                    // Text('Device is ${snapshot.data.toString().split('.')[1]}.'),
                    ? Text('Dispositivo Conectado')
                    : Text('Dispositivo Desconectado'),
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

class LoginScreen extends StatefulWidget {
  Function(String) callback;
  LoginScreen(this.callback);

  @override
  MyCustomFormState createState() {
    return MyCustomFormState();
  }
}

class MyCustomFormState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String cpf;

  Future<http.Response> postData(String data) {
    // DatabaseHelper helper = DatabaseHelper.instance;
    // Users users = Users();
    // users.cpf = data;
    // helper.insertUsers(users);
    return http.post(
      'http://localhost:8083/api/v1/login',
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'data': data,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Build a Form widget using the _formKey created above.
    return Scaffold(
        appBar: AppBar(
          title: Text("Login"),
        ),
        body: Container(
          margin: EdgeInsets.all(50),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      TextFormField(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'CPF',
                        ),
                        validator: (String value) {
                          if (value == null || value.isEmpty) {
                            return 'Insira um cpf';
                          }
                          return null;
                        },
                        onSaved: (String val) {
                          cpf = val;
                          postData(cpf);
                          widget.callback(cpf);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: ElevatedButton(
                          onPressed: () {
                            // Validate will return true if the form is valid, or false if
                            // the form is invalid.
                            if (_formKey.currentState.validate()) {
                              _formKey.currentState.save();
                            }
                          },
                          child: const Text('Entrar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
        ));
  }
}
