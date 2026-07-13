# Documentation – Assignment 7: Replicating Interaction Techniques

## 1. Paper Selection

### Candidates Considered

**Candidate A: ScreenshotMatcher**
Andreas Schmid, Thomas Fischer, Alexander Weichart, Alexander Hartmann, and Raphael Wimmer. 2021. Demonstrating ScreenshotMatcher: Taking Smartphone Photos to Capture Screenshots. In *Mensch und Computer 2021 (MuC '21)*. ACM. https://doi.org/10.1145/3473856.3474029

ScreenshotMatcher lets users capture a high-fidelity screenshot of a computer display by simply photographing it with a smartphone. A companion application running on the PC identifies the corresponding screen region using feature matching (ORB descriptors with brute-force Hamming-distance matching) and returns a clean, high-resolution screenshot to the phone. In lab conditions, the system achieved an 85% success rate with 90 ms processing time. A subsequent remote user study (n = 19) reported a 47% success rate under real-world conditions with a mean response time of 878 ms. The reference implementation is open source.

**Candidate B: DoubleFlip**
Jaime Ruiz and Yang Li. 2011. DoubleFlip: A Motion Gesture Delimiter for Mobile Interaction. In *Proceedings of the SIGCHI Conference on Human Factors in Computing Systems (CHI '11)*. ACM. https://doi.org/10.1145/1978942.1979341

DoubleFlip is a motion-gesture-based technique that uses a smartphone's built-in accelerometer to detect a distinctive "double flip" motion, serving as a reliable delimiter between everyday device movement and intentional gesture input. The recognizer was validated against 2,100 hours of motion data collected from 99 users and shown to be highly resistant to false positives while maintaining a high recognition rate.

The two candidates were deliberately chosen to represent distinct interaction paradigms — computer-vision-based sensing (ScreenshotMatcher) versus inertial motion-gesture sensing (DoubleFlip) — to ensure a genuine comparison rather than a choice between two closely related approaches.

### Selection Rationale

We selected **ScreenshotMatcher** for replication, for the following reasons:

- **Well-scoped core problem.** The central technical challenge — feature matching between a photographed image and a screen region — is self-contained and can be implemented with standard, freely available libraries (e.g., OpenCV's ORB detector and brute-force matcher), without requiring model training or dataset collection.
- **Fits the two-week timeframe.** Unlike more complex systems, the implementation does not depend on specialized hardware; it only requires a smartphone camera and a PC on the same network.
- **Existing evaluation data available.** The published lab and field results (success rate, latency) provide a concrete benchmark against which our own replication can be compared and discussed.
- **Open-source reference implementation.** The original codebase is publicly available, which reduces implementation risk and can serve as an orientation point without being directly copied.
- **Strong live-demo potential.** The interaction is immediately visible and compelling: the user takes a photo, and a clean screenshot appears moments later — well suited to the 8–10-minute live demonstration required for this assignment.

DoubleFlip was considered a valid alternative and is technically feasible within the same timeframe. It was ultimately not selected because its core interaction — recognizing a delimiter gesture — is less visually compelling as a live demonstration than the immediate, tangible result produced by ScreenshotMatcher.

### References

1. Andreas Schmid, Thomas Fischer, Alexander Weichart, Alexander Hartmann, and Raphael Wimmer. 2021. Demonstrating ScreenshotMatcher: Taking Smartphone Photos to Capture Screenshots. In *Mensch und Computer 2021 (MuC '21)*. ACM. https://doi.org/10.1145/3473856.3474029
2. Jaime Ruiz and Yang Li. 2011. DoubleFlip: A Motion Gesture Delimiter for Mobile Interaction. In *Proceedings of the SIGCHI Conference on Human Factors in Computing Systems (CHI '11)*. ACM. https://doi.org/10.1145/1978942.1979341