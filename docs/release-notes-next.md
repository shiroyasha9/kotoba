## kotoba next

### Changed

- Long dictations come about 1.5 s sooner with MAI-Transcribe-2 via OpenRouter: while you speak, kotoba sends each part that ends at a short pause, so at the stop it waits only for the last part. Where you paused, the text can now start a new sentence.

### Fixed

- With AirPods as the Mac’s default mic, kotoba records from the built-in mic. When the built-in mic does not open, kotoba now says so instead of recording from the AirPods, which switched them to call quality.
- A press right after you click Undo now stops the resumed dictation. Before, it could start a second recording over the first and mix their audio. Quitting while a dictation starts or resumes now keeps it for the next launch.
