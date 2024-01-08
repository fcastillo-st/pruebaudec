FROM adoptopenjdk/openjdk11:latest
RUN mkdir /opt/app
COPY Pruebas_Udec-1.0.0-SNAPSHOT.jar /opt/app
CMD ["java", "-jar", "/opt/app/Pruebas_Udec-1.0.0-SNAPSHOT.jar"]