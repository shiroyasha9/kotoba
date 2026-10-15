// Command-line helpers shared by `run.ts` and `review/server.ts`.

export function fail(message: string): never {
	console.error(message);
	process.exit(1);
}

/** Parses `--name` as an integer >= `min`; undefined when the flag is absent. */
export function intArg<K extends string>(values: { [P in K]?: string }, name: K, min: number): number | undefined {
	const raw = values[name];
	if (raw === undefined) return undefined;
	const n = Number(raw);
	if (!(Number.isInteger(n) && n >= min)) fail(`--${name} must be an integer >= ${min}`);
	return n;
}
