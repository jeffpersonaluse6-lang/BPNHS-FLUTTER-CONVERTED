// GENERATED from C:/BPNHS/BPNHS/src/assets/stair_waypoint_guides.json.
// Re-run the sync script after editing waypoint guides.

class StairWaypointGuide {
  final String id;
  final String buildingId;
  final int floorA;
  final int floorB;
  final List<List<double>> pointsAtoB;

  const StairWaypointGuide({
    required this.id,
    required this.buildingId,
    required this.floorA,
    required this.floorB,
    required this.pointsAtoB,
  });

  bool connects(int fromFloor, int toFloor) {
    return (fromFloor == floorA && toFloor == floorB) ||
        (fromFloor == floorB && toFloor == floorA);
  }

  List<List<double>> orderedPoints(int fromFloor, int toFloor) {
    if (fromFloor == floorA && toFloor == floorB) {
      return <List<double>>[
        for (final point in pointsAtoB) <double>[point[0], point[1]],
      ];
    }

    if (fromFloor == floorB && toFloor == floorA) {
      return <List<double>>[
        for (final point in pointsAtoB.reversed) <double>[point[0], point[1]],
      ];
    }

    return const <List<double>>[];
  }
}

const List<StairWaypointGuide> stairWaypointGuides = <StairWaypointGuide>[
  StairWaypointGuide(
    id: '9c51427891544a238879a9f02a96256c',
    buildingId: 'e25b979279324b40acbd92e619a2cd75',
    floorA: 3,
    floorB: 2,
    pointsAtoB: <List<double>>[
      <double>[1735.0437904681505, 132.26333551371857],
      <double>[1733.071041110438, 202.80515889513046],
      <double>[1709.8125622374537, 203.61274496710908],
      <double>[1711.2582944546325, 162.65033214704954],
    ],
  ),
  StairWaypointGuide(
    id: '051c373035404d0d80675117b0e2ec67',
    buildingId: 'e25b979279324b40acbd92e619a2cd75',
    floorA: 4,
    floorB: 3,
    pointsAtoB: <List<double>>[
      <double>[1710.2412251738674, 206.07862775107674],
      <double>[1711.9279127605757, 134.03297226167797],
    ],
  ),
  StairWaypointGuide(
    id: 'e980f854d99c43dcac1cf6aea0179c11',
    buildingId: 'e25b979279324b40acbd92e619a2cd75',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[1711.6365079541495, 132.56148959638438],
      <double>[1735.2180212559251, 132.72300681078008],
      <double>[1736.510158971091, 205.56727050325173],
      <double>[1707.9216120230478, 205.405753288856],
      <double>[1710.8289218821708, 157.9196922565131],
    ],
  ),
  StairWaypointGuide(
    id: '8b56b1ef52ab4866847ee56df202be9f',
    buildingId: 'e25b979279324b40acbd92e619a2cd75',
    floorA: 4,
    floorB: 3,
    pointsAtoB: <List<double>>[
      <double>[1475.6441791719046, 204.4390805192803],
      <double>[1475.8851345414344, 133.83915724706011],
      <double>[1451.5486422189285, 134.08011261658987],
      <double>[1452.7534190665774, 163.71762306875056],
    ],
  ),
  StairWaypointGuide(
    id: '6543d24ccd55439cad17cad2048504bd',
    buildingId: 'e25b979279324b40acbd92e619a2cd75',
    floorA: 3,
    floorB: 2,
    pointsAtoB: <List<double>>[
      <double>[1454.0124045523928, 208.26945478466394],
      <double>[1474.4936109624225, 208.26945478466394],
      <double>[1473.047878745244, 134.05520096949732],
      <double>[1452.5666723352142, 134.05520096949732],
      <double>[1452.5666723352142, 165.13844363883658],
    ],
  ),
  StairWaypointGuide(
    id: '4054a10a4c854fc0aeb6828fc12585e0',
    buildingId: 'e25b979279324b40acbd92e619a2cd75',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[1450.1896085906947, 205.58290474029235],
      <double>[1474.5261009132007, 205.58290474029235],
      <double>[1473.5622794350816, 132.3324724032448],
      <double>[1453.3220283945816, 132.3324724032448],
      <double>[1452.5991622859924, 164.62049192023287],
    ],
  ),
  StairWaypointGuide(
    id: '6682242a64c84baabfd67e2d6acf5134',
    buildingId: '3e0a44a3bf1149e8af682beebab7fd84',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[2346.387464458427, 116.60000000000002],
      <double>[2345.5874644584273, 185.39999999999998],
    ],
  ),
  StairWaypointGuide(
    id: 'd5727769a7b74a65b81d0b4031ce7972',
    buildingId: 'ad9da5042e1247c4b21f3f95af4d6659',
    floorA: 4,
    floorB: 3,
    pointsAtoB: <List<double>>[
      <double>[1476.3947605360559, 206.5327337570244],
      <double>[1475.4309390579367, 133.52325678950666],
      <double>[1450.8534913659012, 133.7642121590364],
      <double>[1452.2992235830798, 174.96758034862563],
    ],
  ),
  StairWaypointGuide(
    id: '7afd961c2b6e4bf890aefd640479b552',
    buildingId: 'ad9da5042e1247c4b21f3f95af4d6659',
    floorA: 4,
    floorB: 3,
    pointsAtoB: <List<double>>[
      <double>[1711.6778641703418, 206.45673868778917],
      <double>[1712.756253684223, 134.92356760032746],
      <double>[1735.0429703044374, 135.28303077162124],
      <double>[1737.5592125034937, 180.2159271833434],
    ],
  ),
  StairWaypointGuide(
    id: '3dfc5311e28e427e8cd5bfa8f6f0e8f2',
    buildingId: 'ad9da5042e1247c4b21f3f95af4d6659',
    floorA: 3,
    floorB: 2,
    pointsAtoB: <List<double>>[
      <double>[1475.9600525419503, 204.11323581574482],
      <double>[1475.7374984491012, 133.11848019683504],
      <double>[1452.8144268856286, 133.78614247538286],
      <double>[1452.8144268856286, 166.05648593852362],
    ],
  ),
  StairWaypointGuide(
    id: 'c5677cb703ee4bf4802402f57f13de0b',
    buildingId: 'ad9da5042e1247c4b21f3f95af4d6659',
    floorA: 3,
    floorB: 2,
    pointsAtoB: <List<double>>[
      <double>[1711.3719198662081, 208.28542372569834],
      <double>[1711.3719198662081, 133.10734843241275],
      <double>[1735.9493675582437, 133.34830380194248],
      <double>[1735.4674568191842, 160.09434981974607],
    ],
  ),
  StairWaypointGuide(
    id: '8c8dd3ffe4ef4e459c285d023dc36a9d',
    buildingId: 'ad9da5042e1247c4b21f3f95af4d6659',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[1475.1539648927298, 208.88409025124133],
      <double>[1473.949188045081, 133.94697032748553],
      <double>[1451.781294048343, 134.18792569701526],
      <double>[1452.2632047874026, 154.66913210704496],
    ],
  ),
  StairWaypointGuide(
    id: 'c0f727fab6e74c38a132b84cc7fd2997',
    buildingId: 'ad9da5042e1247c4b21f3f95af4d6659',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[1709.691622110938, 207.03184360254406],
      <double>[1709.691622110938, 135.13920934378856],
      <double>[1735.9324336153836, 134.06081982990733],
      <double>[1734.1351177589147, 163.1773367047033],
    ],
  ),
  StairWaypointGuide(
    id: '7cb3ea185b3e4b898917a8e32017b90e',
    buildingId: '3c9bd7b3dbe64d56a8a11cfba31cf867',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[777.1046347631434, 835.8750203616497],
      <double>[777.4970008640946, 795.6641780363728],
    ],
  ),
  StairWaypointGuide(
    id: 'bdcea1aca3884491aa07d3526ecdf4b2',
    buildingId: '4ee5fcb4a47044558d9310134c5da1b9',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[2345.6374299212275, 117.55207207587351],
      <double>[2347.959809525437, 178.51453668635864],
    ],
  ),
  StairWaypointGuide(
    id: 'da96c84adeee4e2fa65e1dd69558c8e9',
    buildingId: '4ee5fcb4a47044558d9310134c5da1b9',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[1990.5143933725874, 202.66136782229597],
      <double>[1989.648247559873, 132.503556992436],
      <double>[1965.8292377102296, 134.23584861786463],
      <double>[1966.6953835229435, 170.6139727518661],
    ],
  ),
  StairWaypointGuide(
    id: '6538aff7fcb5417cad6c96b70449c337',
    buildingId: '199c297d98ea4080a12a4c989fa0be84',
    floorA: 4,
    floorB: 3,
    pointsAtoB: <List<double>>[
      <double>[1472.1340273422395, 202.11554217166037],
      <double>[1474.7324647803823, 134.12309587358618],
      <double>[1452.21267364981, 131.95773134180035],
      <double>[1449.1811633053098, 172.2335116330163],
    ],
  ),
  StairWaypointGuide(
    id: 'c7768e68fe224d0795461bcfd21ba230',
    buildingId: '199c297d98ea4080a12a4c989fa0be84',
    floorA: 4,
    floorB: 3,
    pointsAtoB: <List<double>>[
      <double>[1711.2984046537774, 202.95537071195406],
      <double>[1711.2984046537774, 132.83735817879344],
      <double>[1737.5625399325215, 132.83735817879344],
      <double>[1738.044450671581, 171.39021730355526],
    ],
  ),
  StairWaypointGuide(
    id: '1f8d8e86c98b45eb9804676ae054401e',
    buildingId: '199c297d98ea4080a12a4c989fa0be84',
    floorA: 3,
    floorB: 2,
    pointsAtoB: <List<double>>[
      <double>[1451.6600293403399, 208.20596008569015],
      <double>[1475.0251354744353, 206.76810740051502],
      <double>[1474.3062091318477, 131.99976777140935],
      <double>[1453.4573451968088, 132.71869411399692],
      <double>[1451.6600293403399, 153.92702122032975],
    ],
  ),
  StairWaypointGuide(
    id: 'a6602c74d66c475cad2bd171f7444851',
    buildingId: '199c297d98ea4080a12a4c989fa0be84',
    floorA: 3,
    floorB: 2,
    pointsAtoB: <List<double>>[
      <double>[1733.3273631427132, 206.68866554866798],
      <double>[1736.2303376479745, 134.40460036766416],
      <double>[1710.684162001676, 132.37251821398132],
      <double>[1710.3938645511498, 159.9507760139627],
    ],
  ),
  StairWaypointGuide(
    id: '284e489e12b4479a9f2f58d09e716723',
    buildingId: '199c297d98ea4080a12a4c989fa0be84',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[1453.5249316916477, 209.31372630152813],
      <double>[1472.9069974191345, 210.28282958790248],
      <double>[1473.5530662767176, 134.69277325070354],
      <double>[1453.363414477252, 133.56215274993346],
      <double>[1451.4252079045034, 155.2054594789605],
    ],
  ),
  StairWaypointGuide(
    id: 'fc196814ef8d4d66b3d15bbd3914d589',
    buildingId: '199c297d98ea4080a12a4c989fa0be84',
    floorA: 2,
    floorB: 1,
    pointsAtoB: <List<double>>[
      <double>[1711.045114575639, 206.1245494178761],
      <double>[1737.7911605934426, 207.81123700458443],
      <double>[1736.104473006734, 132.63316171129878],
      <double>[1710.804159206109, 131.91029560270948],
      <double>[1709.8403377279901, 153.8372342299178],
    ],
  ),
];
