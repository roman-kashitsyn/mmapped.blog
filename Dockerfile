FROM racket/racket:8.2

RUN /bin/bash -c yes | raco pkg install pollen
COPY . sources
RUN cd sources && raco pollen reset && cd ..
RUN raco pollen publish sources blog && rm sources/template.html
RUN tar cf blog.tar blog && gzip blog.tar
