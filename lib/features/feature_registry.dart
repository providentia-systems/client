import 'package:providentia/core/architecture/feature_descriptor.dart';
import 'package:providentia/features/ai_integration/ai_integration_feature.dart';
import 'package:providentia/features/catalog/catalog_feature.dart';
import 'package:providentia/features/homes/homes_feature.dart';
import 'package:providentia/features/identity/identity_feature.dart';
import 'package:providentia/features/inventory/inventory_feature.dart';
import 'package:providentia/features/purchasing/purchasing_feature.dart';
import 'package:providentia/features/reporting/reporting_feature.dart';
import 'package:providentia/features/shopping/shopping_feature.dart';

const List<FeatureDescriptor> featureRegistry = <FeatureDescriptor>[
  identityFeature,
  homesFeature,
  catalogFeature,
  inventoryFeature,
  purchasingFeature,
  shoppingFeature,
  aiIntegrationFeature,
  reportingFeature,
];
