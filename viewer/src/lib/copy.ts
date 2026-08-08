export const COPY = {
  board: {
    meeting: {
      headlineWithName: (name: string) => `${name} is in a meeting`,
      headline: 'In a meeting',
      supporting: 'Better to wait.',
    },
    callOkay: {
      headlineWithName: (name: string) =>
        `${name} is in Meeting, but it's fine to ring through`,
      headline: "In Meeting, but it's fine to ring through",
      supporting: "He said to go ahead and interrupt.",
    },
    generic: {
      headline: 'Meeting status unavailable',
      supporting: 'Check again before you call.',
      offlineSupporting: 'Connect to the internet, then check again.',
    },
    unpaired: {
      headline: 'Not connected',
      supporting: 'Open the viewer link or enter the code he shared.',
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
    lede: 'Ask him for the viewer link or code. The link keeps working until he rotates it.',
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
