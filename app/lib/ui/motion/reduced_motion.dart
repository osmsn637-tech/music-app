import 'package:flutter/widgets.dart';

/// True when the platform asks for reduced motion (OS accessibility setting).
/// Every motion widget below collapses to its resting state when this is on —
/// motion is decorative; state must always be legible without it.
bool reducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
