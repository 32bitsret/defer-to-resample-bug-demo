.PHONY: both stock fixed clean
both:
	./run_both.sh
clean:
	rm -rf .venv-stock .venv-fixed logs
