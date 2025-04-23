from setuptools import setup, find_packages

with open("requirements.txt") as f:
    requirements = f.read().splitlines()

setup(
    name="sparkbaas",
    version="0.1.0",
    packages=find_packages(),
    include_package_data=True,
    install_requires=requirements,
    python_requires=">=3.8",
    entry_points={
        "console_scripts": [
            "spark=sparkbaas.cli:main",
        ],
    },
    author="SparkBaaS Team",
    author_email="info@sparkbaas.io",
    description="CLI tool for SparkBaaS - A DevOps-first Backend as a Service",
    keywords="baas, backend, database, serverless, devops",
    project_urls={
        "Source Code": "https://github.com/sparkbaas/sparkbaas",
    },
)