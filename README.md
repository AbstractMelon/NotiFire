# NotiFire 🔥

A fire-themed reminders app built with Flutter that runs locally on your device with a beautiful dark UI.

## Features

### Core Functionality

- **Customizable Reminders**: Create reminders with titles, descriptions, and specific dates/times
- **Local-Only Storage**: All data stored locally on your device for privacy
- **Fire & Dark Theme**: Beautiful dark UI with fire-inspired color scheme
- **User-Friendly Interface**: Intuitive design for quick and easy reminder creation

### Special Reminder Types

- **Wake-Up Reminders**: Set reminders for when you wake up (no more throw pillows at the door!)
- **Repeating Reminders**: Set reminders to repeat daily, weekly, monthly, or yearly
- **Weekly Customization**: Choose specific days of the week for repeating weekly reminders

### Additional Features

- **Notification Management**: Receive timely alerts for all your reminders
- **Active & Completed Views**: Toggle between active and completed reminders
- **Swipe Actions**: Quickly mark reminders as complete or delete them with intuitive swipe gestures
- **Custom Wake-Up Time**: Set your regular wake-up time for scheduling morning reminders

## Installation

### Prerequisites

- Flutter 3.0 or higher
- Dart 2.17 or higher
- Android Studio or VS Code with Flutter extensions

### Setup

1. Clone this repository

   ```
   git clone https://github.com/yourusername/notifire.git
   ```

2. Navigate to the project directory

   ```
   cd notifire
   ```

3. Install dependencies

   ```
   flutter pub get
   ```

4. Run the app
   ```
   flutter run
   ```

## How It Works

NotiFire uses Flutter's local notifications system to schedule reminders at specific times. All data is stored locally on your device using shared preferences, making sure that your reminder data stays private.

The app follows a clean architecture pattern with:

- Models for data representation
- Provider for state management
- Local storage for data persistence
- UI components for the user interface

## Special Features

### Wake-Up Reminders

The "Remind Me When I Wake Up" feature replaces the old "throw pillow at door" strategy. Simply set a reminder with the wake-up option, and it will notify you at your pre-set wake-up time.

### Custom Themes

The app comes with multiple fire-inspired themes:

- **Fire & Dark**: Default theme with fire colors on a dark background
- **Pure Dark**: Minimalist dark theme with orange accents
- **Lava**: Intense red and black theme

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
