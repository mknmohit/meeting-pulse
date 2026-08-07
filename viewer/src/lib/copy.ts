export const COPY = {
  board: {
    available: {
      headlineWithName: (name: string) => `${name} is free`,
      headline: 'Free',
      supporting: 'Go ahead.',
    },
    busy: {
      headlineWithName: (name: string) => `${name} is on a call`,
      headline: 'On a call',
      supporting: 'Better to wait.',
    },
    callOkay: "He said it's fine to interrupt.",
    unavailable: {
      headline: 'No signal',
      supporting:
        'His Mac stopped reporting a few minutes ago. This could be wrong either way, so assume he might be busy.',
    },
    unpaired: {
      headline: 'Not connected',
      supporting: 'Ask him for a code and enter it below.',
    },
    offline: {
      headline: 'No signal',
      supporting: 'Your phone is offline. This is the last thing we heard.',
    },
    schemaTooNew: {
      headline: 'No signal',
      supporting:
        "This page is out of date and can't read the latest status. Reload it.",
    },
  },
  rail: {
    checkedJustNow: 'Checked just now',
    checkedSeconds: (seconds: number) => `Checked ${seconds} seconds ago`,
    checkedMinute: (minutes: number) =>
      `Checked ${minutes} minute${minutes === 1 ? '' : 's'} ago`,
    checkedMinutes: (minutes: number) => `Checked ${minutes} minutes ago`,
    checkedAWhile: 'Checked a while ago',
    checkAgain: 'Check again',
    checking: 'Checking',
  },
  pairing: {
    heading: 'Enter the code',
    lede: 'Ask him for a code from the menu bar. It works once and expires in ten minutes.',
    fieldLabel: 'Code',
    button: 'Connect',
    invalid: "That code didn't work. Ask for a fresh one.",
    rateLimited: 'Too many tries. Wait a few minutes and try again.',
    offline: "You're offline. Connect to the internet and try again.",
    evicted: 'This device was signed out. Ask him for a new code.',
    addToHomeScreen: "Add this to your home screen so it's one tap away.",
  },
} as const;

export type CopyState = keyof typeof COPY.board;
