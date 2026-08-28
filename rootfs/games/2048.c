// SPDX-License-Identifier: MIT
//
// 2048 for the Game Stick's framebuffer console.
//
// No 2048 package exists for armv7 in Alpine, so this is built statically
// against musl with the armv7-unknown-linux-musleabihf toolchain and dropped in
// /usr/local/bin. Plain ANSI + termios, so it works on the fbcon console with
// no ncurses dependency.
//
// Controls: arrow keys or WASD/HJKL, r restarts, q quits.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <termios.h>
#include <unistd.h>

#define N 4

static int board[N][N];
static unsigned long score;
static struct termios saved_termios;

static void term_restore(void)
{
	tcsetattr(STDIN_FILENO, TCSANOW, &saved_termios);
	printf("\033[?25h");		/* show cursor */
	fflush(stdout);
}

static void term_raw(void)
{
	struct termios t;

	tcgetattr(STDIN_FILENO, &saved_termios);
	t = saved_termios;
	t.c_lflag &= ~(ICANON | ECHO);
	t.c_cc[VMIN] = 1;
	t.c_cc[VTIME] = 0;
	tcsetattr(STDIN_FILENO, TCSANOW, &t);
	printf("\033[?25l");		/* hide cursor */
}

static int tile_colour(int v)
{
	switch (v) {
	case 2:    return 37;
	case 4:    return 36;
	case 8:    return 32;
	case 16:   return 33;
	case 32:   return 35;
	case 64:   return 31;
	case 128:  return 96;
	case 256:  return 94;
	case 512:  return 92;
	case 1024: return 93;
	default:   return 91;
	}
}

static int free_cells(void)
{
	int r, c, n = 0;

	for (r = 0; r < N; r++)
		for (c = 0; c < N; c++)
			if (!board[r][c])
				n++;
	return n;
}

static void spawn(void)
{
	int n = free_cells(), pick, r, c;

	if (!n)
		return;
	pick = rand() % n;
	for (r = 0; r < N; r++) {
		for (c = 0; c < N; c++) {
			if (board[r][c])
				continue;
			if (pick-- == 0) {
				board[r][c] = (rand() % 10) ? 2 : 4;
				return;
			}
		}
	}
}

static void draw(void)
{
	int r, c;

	printf("\033[H\033[2J");
	printf("  2048        score: %lu\n\n", score);
	for (r = 0; r < N; r++) {
		printf("  +------+------+------+------+\n  ");
		for (c = 0; c < N; c++) {
			int v = board[r][c];

			if (v)
				printf("|\033[1;%dm%5d \033[0m", tile_colour(v), v);
			else
				printf("|      ");
		}
		printf("|\n");
	}
	printf("  +------+------+------+------+\n");
	printf("\n  arrows/wasd move   r restart   q quit\n");
	fflush(stdout);
}

/* Slide and merge one line towards index 0. Returns 1 if anything changed. */
static int slide(int *line)
{
	int tmp[N], i, j = 0, moved = 0;

	memset(tmp, 0, sizeof(tmp));
	for (i = 0; i < N; i++)
		if (line[i])
			tmp[j++] = line[i];

	for (i = 0; i < N - 1; i++) {
		if (tmp[i] && tmp[i] == tmp[i + 1]) {
			tmp[i] *= 2;
			score += tmp[i];
			for (j = i + 1; j < N - 1; j++)
				tmp[j] = tmp[j + 1];
			tmp[N - 1] = 0;
		}
	}
	for (i = 0; i < N; i++) {
		if (line[i] != tmp[i])
			moved = 1;
		line[i] = tmp[i];
	}
	return moved;
}

/* dir: 0 left, 1 right, 2 up, 3 down */
static int move(int dir)
{
	int line[N], i, k, moved = 0;

	for (i = 0; i < N; i++) {
		for (k = 0; k < N; k++) {
			switch (dir) {
			case 0: line[k] = board[i][k];         break;
			case 1: line[k] = board[i][N - 1 - k]; break;
			case 2: line[k] = board[k][i];         break;
			default: line[k] = board[N - 1 - k][i]; break;
			}
		}
		if (slide(line))
			moved = 1;
		for (k = 0; k < N; k++) {
			switch (dir) {
			case 0: board[i][k]         = line[k]; break;
			case 1: board[i][N - 1 - k] = line[k]; break;
			case 2: board[k][i]         = line[k]; break;
			default: board[N - 1 - k][i] = line[k]; break;
			}
		}
	}
	return moved;
}

static int can_move(void)
{
	int r, c;

	if (free_cells())
		return 1;
	for (r = 0; r < N; r++)
		for (c = 0; c < N; c++) {
			if (c + 1 < N && board[r][c] == board[r][c + 1])
				return 1;
			if (r + 1 < N && board[r][c] == board[r + 1][c])
				return 1;
		}
	return 0;
}

static void reset(void)
{
	memset(board, 0, sizeof(board));
	score = 0;
	spawn();
	spawn();
}

int main(void)
{
	srand((unsigned)time(NULL) ^ (unsigned)getpid());
	term_raw();
	atexit(term_restore);
	reset();

	for (;;) {
		int dir = -1, ch;

		draw();
		if (!can_move()) {
			printf("\n  no moves left - final score %lu. r restart, q quit.\n",
			       score);
			fflush(stdout);
		}

		ch = getchar();
		if (ch == EOF || ch == 'q' || ch == 'Q')
			break;
		if (ch == 'r' || ch == 'R') {
			reset();
			continue;
		}
		if (ch == '\033') {			/* arrow keys */
			if (getchar() != '[')
				continue;
			switch (getchar()) {
			case 'A': dir = 2; break;
			case 'B': dir = 3; break;
			case 'C': dir = 1; break;
			case 'D': dir = 0; break;
			}
		} else {
			switch (ch) {
			case 'a': case 'h': dir = 0; break;
			case 'd': case 'l': dir = 1; break;
			case 'w': case 'k': dir = 2; break;
			case 's': case 'j': dir = 3; break;
			}
		}

		if (dir >= 0 && move(dir))
			spawn();
	}

	printf("\033[H\033[2J");
	return 0;
}
