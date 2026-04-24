'use strict';

self.runOnStartup(async runtime => {
    const STORAGE_KEY = 'fisherman.balance';
    const CHANNEL_CANDIDATES = ['FishermanBridge', 'FlutterBridge', 'fishermanBridge'];
    const state = {
        balance: 0,
        lastBalance: null,
        ready: false,
        pollTimerId: null,
    };

    function toNumber(value, fallback) {
        const numericValue = Number(value);
        return Number.isFinite(numericValue) ? numericValue : fallback;
    }

    function getBalance() {
        return toNumber(runtime.globalVars.balance, state.balance);
    }

    function persistBalance(balance) {
        state.balance = balance;
        state.lastBalance = balance;
        try {
            localStorage.setItem(STORAGE_KEY, String(balance));
        } catch (error) {
            console.warn('[FishermanBridge] Failed to persist balance:', error);
        }
    }

    function postToFlutter(type, payload) {
        const message = JSON.stringify({
            type,
            payload,
            balance: getBalance(),
            ready: state.ready,
            timestamp: Date.now(),
        });

        for (const channelName of CHANNEL_CANDIDATES) {
            const channel = window[channelName];
            if (channel && typeof channel.postMessage === 'function') {
                channel.postMessage(message);
                return true;
            }
        }

        window.dispatchEvent(new CustomEvent('fisherman-bridge-message', {
            detail: JSON.parse(message),
        }));

        return false;
    }

    function emitStateChange(reason) {
        postToFlutter('balance', {
            reason,
            balance: getBalance(),
        });
    }

    function setBalance(nextBalance, reason = 'flutter') {
        const numericBalance = toNumber(nextBalance, getBalance());
        runtime.globalVars.balance = numericBalance;
        persistBalance(numericBalance);
        emitStateChange(reason);
        return numericBalance;
    }

    function adjustBalance(delta, reason = 'flutter-adjust') {
        return setBalance(getBalance() + toNumber(delta, 0), reason);
    }

    function syncFromGame(reason = 'game') {
        const currentBalance = getBalance();
        if (currentBalance === state.lastBalance)
            return false;
        persistBalance(currentBalance);
        emitStateChange(reason);
        return true;
    }

    function loadPersistedBalance() {
        try {
            const rawBalance = localStorage.getItem(STORAGE_KEY);
            if (rawBalance === null || rawBalance === '')
                return getBalance();

            return toNumber(rawBalance, getBalance());
        } catch (error) {
            console.warn('[FishermanBridge] Failed to read persisted balance:', error);
            return getBalance();
        }
    }

    const initialBalance = loadPersistedBalance();
    runtime.globalVars.balance = initialBalance;
    persistBalance(initialBalance);

    window.FishermanFlutterBridge = {
        getState() {
            return {
                ready: state.ready,
                balance: getBalance(),
                storageKey: STORAGE_KEY,
            };
        },
        getBalance,
        setBalance,
        adjustBalance,
        syncFromGame,
        notify(eventName, payload = {}) {
            postToFlutter(eventName, payload);
        },
        destroy() {
            if (state.pollTimerId !== null) {
                clearInterval(state.pollTimerId);
                state.pollTimerId = null;
            }
            delete window.FishermanFlutterBridge;
            delete window.fishermanFlutterBridge;
            state.ready = false;
        },
    };

    window.fishermanFlutterBridge = window.FishermanFlutterBridge;

    state.ready = true;
    emitStateChange('ready');

    state.pollTimerId = setInterval(() => {
        syncFromGame('poll');
    }, 250);

    window.addEventListener('beforeunload', () => {
        if (state.pollTimerId !== null) {
            clearInterval(state.pollTimerId);
            state.pollTimerId = null;
        }
    });
});